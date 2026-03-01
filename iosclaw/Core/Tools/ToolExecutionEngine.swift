import EventKit
import Foundation

enum ToolCommand: Equatable {
    case webSearch(query: String)
    case readFile(name: String)
    case writeFile(name: String, content: String)
    case createReminder(title: String)

    nonisolated static func parse(from prompt: String) -> ToolCommand? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let query = trimmed.value(afterPrefixes: ["search:", "web:", "web search:"]) {
            return .webSearch(query: query)
        }

        if let name = trimmed.value(afterPrefixes: ["read file:", "open file:"]) {
            return .readFile(name: name)
        }

        if let payload = trimmed.value(afterPrefixes: ["write file:", "save file:"]) {
            let parts = payload.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return .writeFile(
                name: parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
                content: parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        if let title = trimmed.value(afterPrefixes: ["remind:", "add reminder:"]) {
            return .createReminder(title: title)
        }

        return nil
    }

    nonisolated var toolID: String {
        switch self {
        case .webSearch:
            return BuiltInTool.webSearch.rawValue
        case .readFile, .writeFile:
            return BuiltInTool.fileReadWrite.rawValue
        case .createReminder:
            return BuiltInTool.reminders.rawValue
        }
    }

    nonisolated var requiresClientApproval: Bool {
        switch self {
        case .writeFile:
            return true
        case .webSearch, .readFile, .createReminder:
            return false
        }
    }

    nonisolated var approvalSummary: String {
        switch self {
        case let .writeFile(name, _):
            return "This will write to `\(name)` inside the app sandbox."
        case let .webSearch(query):
            return "This will search for `\(query)`."
        case let .readFile(name):
            return "This will read `\(name)` from the app sandbox."
        case let .createReminder(title):
            return "This will create a reminder named `\(title)`."
        }
    }
}

struct ToolExecutionResult: Equatable {
    let command: ToolCommand
    let output: String
}

enum ToolExecutionError: LocalizedError {
    case unknownTool
    case approvalDenied
    case malformedCommand
    case missingReminderCalendar

    var errorDescription: String? {
        switch self {
        case .unknownTool:
            return "The requested tool is not in the secure registry."
        case .approvalDenied:
            return "The action was blocked because approval was denied or unavailable."
        case .malformedCommand:
            return "The command format is invalid."
        case .missingReminderCalendar:
            return "No reminders calendar is available for this device account."
        }
    }
}

actor ToolExecutionEngine {
    private let registry: ToolRegistry
    private let approvalCoordinator: ApprovalCoordinator

    init(
        registry: ToolRegistry = .secureDefault,
        approvalCoordinator: ApprovalCoordinator = ApprovalCoordinator()
    ) {
        self.registry = registry
        self.approvalCoordinator = approvalCoordinator
    }

    func executeIfNeeded(for prompt: String) async throws -> ToolExecutionResult? {
        guard let command = ToolCommand.parse(from: prompt) else {
            return nil
        }

        guard let tool = registry.tool(named: command.toolID) else {
            throw ToolExecutionError.unknownTool
        }

        // High-risk commands that require explicit client approval are gated in the UI
        // before they are sent into the tool executor.
        if !command.requiresClientApproval {
            let requirement = approvalCoordinator.requirement(for: tool)
            if case let .biometric(reason) = requirement {
                let approvalResult = await approvalCoordinator.requestBiometricApproval(reason: reason)
                guard approvalResult.approved else {
                    throw ToolExecutionError.approvalDenied
                }
            }
        }

        let output: String
        switch command {
        case let .webSearch(query):
            output = try await WebSearchService.search(query: query)
        case let .readFile(name):
            output = try AppSandboxFileService.readFile(named: name)
        case let .writeFile(name, content):
            output = try AppSandboxFileService.writeFile(named: name, content: content)
        case let .createReminder(title):
            output = try await RemindersService.createReminder(title: title)
        }

        return ToolExecutionResult(command: command, output: output)
    }
}

enum WebSearchService {
    nonisolated static func search(query: String, session: URLSession = .shared) async throws -> String {
        guard var components = URLComponents(string: "https://api.duckduckgo.com/") else {
            throw GeminiAPIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1")
        ]

        guard let url = components.url else {
            throw GeminiAPIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw GeminiAPIError.invalidResponse
        }

        let decoded = try parseSearchPayload(data)
        let abstract = decoded.abstract.trimmingCharacters(in: .whitespacesAndNewlines)
        if !abstract.isEmpty {
            return "Search result for \"\(query)\":\n\(abstract)"
        }

        if let firstTopic = decoded.relatedTopics.first, !firstTopic.isEmpty {
            return "Search result for \"\(query)\":\n\(firstTopic)"
        }

        return "No direct search summary was returned for \"\(query)\"."
    }

    nonisolated private static func parseSearchPayload(_ data: Data) throws -> (abstract: String, relatedTopics: [String]) {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let abstract = object?["AbstractText"] as? String ?? ""
        let relatedTopics = flattenTopics(from: object?["RelatedTopics"])
        return (abstract: abstract, relatedTopics: relatedTopics)
    }

    nonisolated private static func flattenTopics(from value: Any?) -> [String] {
        guard let entries = value as? [Any] else { return [] }
        var results: [String] = []

        for entry in entries {
            if let topic = entry as? [String: Any] {
                if let text = topic["Text"] as? String {
                    results.append(text)
                }
                if let nested = topic["Topics"] {
                    results.append(contentsOf: flattenTopics(from: nested))
                }
            }
        }

        return results
    }
}

enum AppSandboxFileService {
    nonisolated static func readFile(named name: String) throws -> String {
        let url = try fileURL(for: name)
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            return "The file exists but is not UTF-8 text."
        }

        return "Read \(url.lastPathComponent):\n\(text)"
    }

    nonisolated static func writeFile(named name: String, content: String) throws -> String {
        let url = try fileURL(for: name)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = content.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: url, options: .atomic)
        return "Saved \(url.lastPathComponent) in the app documents directory."
    }

    nonisolated private static func fileURL(for requestedName: String) throws -> URL {
        let cleaned = requestedName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "..", with: "")
            .replacingOccurrences(of: ":", with: "-")

        guard !cleaned.isEmpty else {
            throw ToolExecutionError.malformedCommand
        }

        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        return documentsDirectory.appendingPathComponent(cleaned)
    }
}

enum RemindersService {
    static func createReminder(title: String) async throws -> String {
        let eventStore = EKEventStore()
        let granted = try await requestAccessIfNeeded(eventStore: eventStore)
        guard granted else {
            throw ToolExecutionError.approvalDenied
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders() ?? eventStore.calendars(for: .reminder).first

        guard reminder.calendar != nil else {
            throw ToolExecutionError.missingReminderCalendar
        }

        try eventStore.save(reminder, commit: true)
        return "Reminder created: \(title)"
    }

    static func requestAccessIfNeeded(eventStore: EKEventStore) async throws -> Bool {
        if #available(iOS 17.0, *) {
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestFullAccessToReminders { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }
}

private extension String {
    nonisolated func value(afterPrefixes prefixes: [String]) -> String? {
        let lowercased = lowercased()
        for prefix in prefixes {
            if lowercased.hasPrefix(prefix) {
                let index = self.index(startIndex, offsetBy: prefix.count)
                let value = self[index...].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }

        return nil
    }
}
