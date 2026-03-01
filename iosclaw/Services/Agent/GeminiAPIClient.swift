import Foundation

protocol GeminiAPIClientProtocol {
    func generateContent(
        from messages: [AgentService.Message],
        configuration: AppConfiguration,
        plan: AgentExecutionPlan
    ) async throws -> String
}

final class GeminiAPIClient: GeminiAPIClientProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generateContent(
        from messages: [AgentService.Message],
        configuration: AppConfiguration,
        plan: AgentExecutionPlan
    ) async throws -> String {
        guard let apiKey = configuration.geminiAPIKey else {
            throw GeminiAPIError.missingAPIKey
        }

        let request = try makeRequest(
            messages: messages,
            configuration: configuration,
            apiKey: apiKey,
            plan: plan
        )
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw GeminiAPIError.requestFailed(statusCode: httpResponse.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = decoded.candidates
            .first?
            .content
            .parts
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let text, !text.isEmpty else {
            throw GeminiAPIError.emptyResponse
        }

        return text
    }

    private func makeRequest(
        messages: [AgentService.Message],
        configuration: AppConfiguration,
        apiKey: String,
        plan: AgentExecutionPlan
    ) throws -> URLRequest {
        let trimmedBase = configuration.geminiBaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = "\(trimmedBase)/v1beta/models/\(configuration.geminiModel):generateContent?key=\(apiKey)"

        guard let url = URL(string: endpoint) else {
            throw GeminiAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemText = messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let contents = messages
            .filter { $0.role != .system }
            .map { message in
                GeminiContent(
                    role: message.role == .assistant ? "model" : "user",
                    parts: [GeminiPart(text: message.content)]
                )
            }

        let fallbackContents = contents.isEmpty
            ? [GeminiContent(role: "user", parts: [GeminiPart(text: plan.goal)])]
            : contents
        let requestBody = GeminiRequest(
            systemInstruction: systemText.isEmpty ? nil : GeminiInstruction(parts: [GeminiPart(text: systemText)]),
            contents: fallbackContents
        )

        request.httpBody = try JSONEncoder().encode(requestBody)
        return request
    }
}

enum GeminiAPIError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case emptyResponse
    case requestFailed(statusCode: Int, body: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "A Gemini API key is required before the live transport can run."
        case .invalidURL:
            return "The Gemini base URL or model configuration is invalid."
        case .invalidResponse:
            return "The Gemini API returned an unexpected response."
        case .emptyResponse:
            return "The Gemini API returned no candidate text."
        case let .requestFailed(statusCode, body):
            let snippet = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No response body"
            return "Gemini API request failed (\(statusCode)): \(snippet)"
        }
    }
}

private struct GeminiRequest: Encodable {
    let systemInstruction: GeminiInstruction?
    let contents: [GeminiContent]
}

private struct GeminiInstruction: Encodable {
    let parts: [GeminiPart]
}

private struct GeminiContent: Encodable {
    let role: String
    let parts: [GeminiPart]
}

private struct GeminiPart: Encodable {
    let text: String
}

private struct GeminiResponse: Decodable {
    let candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Decodable {
    let content: GeminiCandidateContent
}

private struct GeminiCandidateContent: Decodable {
    let parts: [GeminiCandidatePart]
}

private struct GeminiCandidatePart: Decodable {
    let text: String?
}
