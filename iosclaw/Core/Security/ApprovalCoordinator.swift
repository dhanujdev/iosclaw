import Foundation
import LocalAuthentication

enum ApprovalRequirement: Equatable {
    case none
    case biometric(reason: String)
}

struct BiometricApprovalResult {
    let approved: Bool
    let message: String?
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

    func requestBiometricApproval(reason: String) async -> BiometricApprovalResult {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return BiometricApprovalResult(
                approved: false,
                message: Self.failureMessage(for: error)
            )
        }

        do {
            let approved = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            return BiometricApprovalResult(
                approved: approved,
                message: approved ? nil : "Face ID confirmation was not approved."
            )
        } catch {
            return BiometricApprovalResult(
                approved: false,
                message: Self.failureMessage(for: error)
            )
        }
    }

    private nonisolated static func failureMessage(for error: Error?) -> String {
        guard let laError = error as? LAError else {
            return "Face ID confirmation failed or is unavailable on this device."
        }

        switch laError.code {
        case .biometryNotAvailable:
            return "Face ID is unavailable on this device. The action stayed queued."
        case .biometryNotEnrolled:
            return "Face ID is not configured yet. Enroll biometrics to approve this action."
        case .passcodeNotSet:
            return "A device passcode is required before Face ID approvals can run."
        case .userCancel, .appCancel, .systemCancel:
            return "Face ID confirmation was cancelled. The action stayed queued."
        case .authenticationFailed:
            return "Face ID could not verify your identity. The action stayed queued."
        default:
            return "Face ID confirmation failed or is unavailable on this device."
        }
    }
}
