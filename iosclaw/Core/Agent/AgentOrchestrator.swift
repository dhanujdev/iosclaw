import Foundation

struct AgentExecutionPlan: Identifiable, Codable, Hashable {
    let id: UUID
    let goal: String
    let steps: [AgentPlanStep]
    let createdAt: Date

    nonisolated var planJSON: String {
        let formatter = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "id": id.uuidString,
            "goal": goal,
            "createdAt": formatter.string(from: createdAt),
            "steps": steps.map {
                [
                    "title": $0.title,
                    "state": $0.state.rawValue
                ]
            }
        ]

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"goal\":\"\(goal)\"}"
        }

        return json
    }
}

struct AgentPlanStep: Codable, Hashable {
    let title: String
    let state: AgentLifecycleState
}

enum AgentLifecycleState: String, Codable, Hashable {
    case idle
    case observing
    case planning
    case acting
    case evaluating
    case waitingForApproval
    case completed
    case failed
}

actor AgentOrchestrator {
    private(set) var state: AgentLifecycleState = .idle

    func makePlan(from messages: [AgentService.Message]) -> AgentExecutionPlan {
        state = .observing

        let goal = messages.last(where: { $0.role == .user })?.content ?? "Continue the current task"
        let plan = AgentExecutionPlan(
            id: UUID(),
            goal: goal,
            steps: [
                AgentPlanStep(title: "Observe conversation context", state: .observing),
                AgentPlanStep(title: "Build PLAN.json for the next action", state: .planning),
                AgentPlanStep(title: "Execute the selected tool or model call", state: .acting),
                AgentPlanStep(title: "Evaluate the result before replying", state: .evaluating)
            ],
            createdAt: Date()
        )

        state = .planning
        return plan
    }

    func transition(to newState: AgentLifecycleState) {
        state = newState
    }
}
