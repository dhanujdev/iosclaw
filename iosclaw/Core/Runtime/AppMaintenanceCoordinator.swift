import Foundation

@MainActor
final class AppMaintenanceCoordinator {
    private let taskExecutionStore: TaskExecutionPersistenceController
    private let auditStore: SafetyAuditPersistenceController
    private let preferenceStore: UserPreferencePersistenceController
    private let configuration: AppConfiguration

    init() {
        self.taskExecutionStore = TaskExecutionPersistenceController()
        self.auditStore = SafetyAuditPersistenceController()
        self.preferenceStore = UserPreferencePersistenceController()
        self.configuration = .live
    }

    init(
        taskExecutionStore: TaskExecutionPersistenceController,
        auditStore: SafetyAuditPersistenceController,
        preferenceStore: UserPreferencePersistenceController,
        configuration: AppConfiguration
    ) {
        self.taskExecutionStore = taskExecutionStore
        self.auditStore = auditStore
        self.preferenceStore = preferenceStore
        self.configuration = configuration
    }

    func performLaunchMaintenance() {
        persistSyncHealth()
        recoverInterruptedRuns(reason: "Recovered interrupted agent runs after app launch.")
    }

    func performBackgroundMaintenance() {
        persistSyncHealth()
        recoverInterruptedRuns(reason: "Recovered interrupted agent runs during background maintenance.")
        auditStore.record(
            category: .backgroundExecution,
            severity: .info,
            message: "Background maintenance completed."
        )
    }

    private func persistSyncHealth() {
        preferenceStore.upsert(
            key: "sync.requested",
            value: configuration.enableCloudKitSync ? "true" : "false"
        )
        preferenceStore.upsert(
            key: "sync.mode",
            value: AppModelContainer.syncStatusDescription
        )
        preferenceStore.upsert(
            key: "sync.conflictPolicy",
            value: "Last-write-wins for preferences, preserve local audit trails, and continue local execution when CloudKit is unavailable."
        )

        if let bootstrapIssue = AppModelContainer.bootstrapIssueDescription,
           !bootstrapIssue.isEmpty {
            preferenceStore.upsert(
                key: "sync.bootstrapIssue",
                value: bootstrapIssue
            )
        }

        guard configuration.enableCloudKitSync else {
            auditStore.record(
                category: .cloudSync,
                severity: .info,
                message: "CloudKit sync is disabled. The app is running in local-only mode."
            )
            return
        }

        let validator = ISO8601DateFormatter()
        switch AppModelContainer.syncMode {
        case .cloudKit:
            let timestamp = validator.string(from: .now)
            preferenceStore.upsert(key: "sync.lastValidation", value: timestamp)
            preferenceStore.upsert(key: "sync.lastRecoveryAction", value: "cloudkit_active")
            auditStore.record(
                category: .cloudSync,
                severity: .info,
                message: "CloudKit smoke validation completed successfully."
            )
        case .cloudKitFallback:
            preferenceStore.upsert(key: "sync.lastRecoveryAction", value: "local_fallback")
            let issueSuffix: String
            if let bootstrapIssue = AppModelContainer.bootstrapIssueDescription,
               !bootstrapIssue.isEmpty {
                issueSuffix = " Bootstrap issue: \(bootstrapIssue)"
            } else {
                issueSuffix = ""
            }
            auditStore.record(
                category: .cloudSync,
                severity: .warning,
                message: "CloudKit was requested but the app fell back to local persistence.\(issueSuffix)"
            )
        case .localOnly:
            auditStore.record(
                category: .cloudSync,
                severity: .info,
                message: "CloudKit is not requested. Local persistence remains active."
            )
        }
    }

    private func recoverInterruptedRuns(reason: String) {
        let recoveredCount = taskExecutionStore.recoverInterruptedRuns()
        guard recoveredCount > 0 else { return }

        auditStore.record(
            category: .agentRun,
            severity: .warning,
            message: "\(reason) Recovered \(recoveredCount) run(s)."
        )
    }
}
