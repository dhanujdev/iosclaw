import Foundation

enum ToolRiskLevel: String, CaseIterable, Codable {
    case low
    case medium
    case high
}

struct ToolDefinition: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let summary: String
    let riskLevel: ToolRiskLevel
    let allowedScopes: [String]
}

enum BuiltInTool: String, CaseIterable {
    case webSearch = "web_search"
    case fileReadWrite = "file_read_write"
    case reminders = "reminders"

    var definition: ToolDefinition {
        switch self {
        case .webSearch:
            return ToolDefinition(
                id: rawValue,
                name: "Web Search",
                summary: "Calls an approved read-only endpoint and normalizes results for the agent loop.",
                riskLevel: .medium,
                allowedScopes: ["network.read"]
            )
        case .fileReadWrite:
            return ToolDefinition(
                id: rawValue,
                name: "Files",
                summary: "Reads and writes only within app-controlled sandbox locations.",
                riskLevel: .high,
                allowedScopes: ["files.app_container"]
            )
        case .reminders:
            return ToolDefinition(
                id: rawValue,
                name: "Reminders",
                summary: "Creates and reads reminders after explicit user-granted system permission.",
                riskLevel: .medium,
                allowedScopes: ["reminders.read", "reminders.write"]
            )
        }
    }
}

struct ToolRegistry {
    private(set) var definitions: [ToolDefinition]

    nonisolated static let secureDefault = ToolRegistry(definitions: BuiltInTool.allCases.map(\.definition))

    nonisolated func tool(named name: String) -> ToolDefinition? {
        definitions.first { $0.id == name || $0.name == name }
    }

    nonisolated func requiresHumanApproval(for name: String) -> Bool {
        guard let tool = tool(named: name) else {
            return true
        }

        return tool.riskLevel == .high
    }
}
