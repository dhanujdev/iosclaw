import Foundation

struct AppConfiguration {
    let geminiAPIKey: String?
    let geminiModel: String
    let geminiBaseURL: URL
    let enableCloudKitSync: Bool

    nonisolated var hasGeminiCredentials: Bool {
        geminiAPIKey != nil
    }

    static var live: AppConfiguration {
        let environment = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
        let infoValue = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String
        let resolved = [environment, infoValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let model = resolvedValue(
            environmentKey: "GEMINI_MODEL",
            infoKey: "GEMINI_MODEL",
            defaultValue: "gemini-2.0-flash"
        )
        let baseURLString = resolvedValue(
            environmentKey: "GEMINI_BASE_URL",
            infoKey: "GEMINI_BASE_URL",
            defaultValue: "https://generativelanguage.googleapis.com"
        )
        let baseURL = URL(string: baseURLString) ?? URL(string: "https://generativelanguage.googleapis.com")!

        return AppConfiguration(
            geminiAPIKey: resolved,
            geminiModel: model,
            geminiBaseURL: baseURL,
            enableCloudKitSync: resolvedBool(
                environmentKey: "ENABLE_CLOUDKIT_SYNC",
                infoKey: "ENABLE_CLOUDKIT_SYNC",
                defaultValue: false
            )
        )
    }

    private static func resolvedValue(
        environmentKey: String,
        infoKey: String,
        defaultValue: String
    ) -> String {
        let environment = ProcessInfo.processInfo.environment[environmentKey]
        let infoValue = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String

        return [environment, infoValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? defaultValue
    }

    private static func resolvedBool(
        environmentKey: String,
        infoKey: String,
        defaultValue: Bool
    ) -> Bool {
        let rawValue = resolvedValue(
            environmentKey: environmentKey,
            infoKey: infoKey,
            defaultValue: defaultValue ? "1" : "0"
        ).lowercased()

        switch rawValue {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return defaultValue
        }
    }
}
