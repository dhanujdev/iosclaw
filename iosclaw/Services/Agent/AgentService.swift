import Foundation
import Combine

final class AgentService: ObservableObject {
    enum Role: String, Codable, Hashable {
        case user, assistant, system
    }

    struct Message: Codable, Hashable {
        let role: Role
        let content: String
    }

    private let configuration: AppConfiguration
    private let client: GeminiAPIClientProtocol
    private let orchestrator: AgentOrchestrator
    private let toolExecutor: ToolExecutionEngine

    init(
        configuration: AppConfiguration,
        client: GeminiAPIClientProtocol = GeminiAPIClient(),
        orchestrator: AgentOrchestrator = AgentOrchestrator(),
        toolExecutor: ToolExecutionEngine = ToolExecutionEngine()
    ) {
        self.configuration = configuration
        self.client = client
        self.orchestrator = orchestrator
        self.toolExecutor = toolExecutor
    }

    func generateResponse(to messages: [AgentService.Message]) -> AnyPublisher<String, Never> {
        let subject = PassthroughSubject<String, Never>()

        Task.detached(priority: .userInitiated) { [configuration, client, orchestrator, toolExecutor] in
            let plan = await orchestrator.makePlan(from: messages)
            await orchestrator.transition(to: .acting)

            let response: String
            do {
                if let prompt = messages.last(where: { $0.role == .user })?.content,
                   let toolResult = try await toolExecutor.executeIfNeeded(for: prompt) {
                    response = Self.makeToolResponse(toolResult: toolResult, plan: plan)
                } else if configuration.hasGeminiCredentials {
                    response = try await client.generateContent(
                        from: messages,
                        configuration: configuration,
                        plan: plan
                    )
                } else {
                    response = Self.makeStubResponse(messages: messages, configuration: configuration, plan: plan)
                }
                await orchestrator.transition(to: .evaluating)
            } catch {
                await orchestrator.transition(to: .failed)
                response = Self.makeFailureResponse(error: error, plan: plan)
            }

            for chunk in response.chunks(of: 24) {
                try? await Task.sleep(nanoseconds: 70_000_000)
                subject.send(chunk)
            }

            await orchestrator.transition(to: .completed)
            subject.send(completion: .finished)
        }

        return subject.eraseToAnyPublisher()
    }

    nonisolated private static func makeStubResponse(
        messages: [AgentService.Message],
        configuration: AppConfiguration,
        plan: AgentExecutionPlan
    ) -> String {
        let prompt = messages.last(where: { $0.role == .user })?.content ?? ""
        return """
        Phase 1 shell is active.

        Prompt captured: \(prompt)

        PLAN.json:
        \(plan.planJSON)

        Gemini transport: \(configuration.hasGeminiCredentials ? "configured" : "stub mode")
        Next implementation step: refine tool execution and persist plan state into SwiftData.
        """
    }

    nonisolated private static func makeFailureResponse(error: Error, plan: AgentExecutionPlan) -> String {
        """
        The live agent request failed, so the run stopped before completion.

        Last generated PLAN.json:
        \(plan.planJSON)

        Error:
        \(error.localizedDescription)
        """
    }

    nonisolated private static func makeToolResponse(toolResult: ToolExecutionResult, plan: AgentExecutionPlan) -> String {
        """
        Secure tool execution completed.

        PLAN.json:
        \(plan.planJSON)

        Output:
        \(toolResult.output)
        """
    }
}

private extension String {
    nonisolated func chunks(of size: Int) -> [String] {
        guard size > 0 else { return [] }
        var result: [String] = []
        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(String(self[start..<end]))
            start = end
        }
        return result
    }
}
