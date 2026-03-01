import Foundation
import LocalAuthentication

enum ApprovalRequirement: Equatable {
    case none
    case biometric(reason: String)
}

final class ApprovalCoordinator {
    nonisolated init() {}

    nonisolated func requirement(for tool: ToolDefinition) -> ApprovalRequirement {
        switch tool.riskLevel {
        case .low, .medium:
            return .none
        case .high:
            return .biometric(reason: "Approve \(tool.name) before the agent continues.")
        }
    }

    func requestBiometricApproval(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }

        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            return false
        }
    }
}
