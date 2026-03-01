import Foundation
import SwiftData

enum AppModelContainer {
    enum SyncMode {
        case localOnly
        case cloudKit
        case cloudKitFallback
    }

    struct BootstrapResult {
        let container: ModelContainer
        let syncMode: SyncMode
        let statusDescription: String
        let bootstrapIssueDescription: String?
    }

    @MainActor
    static let bootstrap: BootstrapResult = {
        let schema = Schema([
            ConversationMemory.self,
            MemoryEntry.self,
            TaskExecutionRecord.self,
            UserPreferenceRecord.self,
            PendingApprovalRecord.self,
            ApprovalAuditRecord.self,
            SafetyAuditRecord.self
        ])

        let localConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let cloudConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        let cloudSyncRequested = AppConfiguration.live.enableCloudKitSync

        if cloudSyncRequested {
            do {
                let cloudContainer = try ModelContainer(for: schema, configurations: [cloudConfiguration])
                return BootstrapResult(
                    container: cloudContainer,
                    syncMode: .cloudKit,
                    statusDescription: "CloudKit sync enabled",
                    bootstrapIssueDescription: nil
                )
            } catch {
                let issue = error.localizedDescription

                if let localContainer = try? ModelContainer(for: schema, configurations: [localConfiguration]) {
                    return BootstrapResult(
                        container: localContainer,
                        syncMode: .cloudKitFallback,
                        statusDescription: "CloudKit requested, using local fallback",
                        bootstrapIssueDescription: issue
                    )
                }
            }
        }

        if let localContainer = try? ModelContainer(for: schema, configurations: [localConfiguration]) {
            return BootstrapResult(
                container: localContainer,
                syncMode: cloudSyncRequested ? .cloudKitFallback : .localOnly,
                statusDescription: cloudSyncRequested
                    ? "CloudKit requested, using local fallback"
                    : "Local-only persistence",
                bootstrapIssueDescription: nil
            )
        }

        fatalError("Failed to create ModelContainer")
    }()

    @MainActor
    static let shared: ModelContainer = {
        bootstrap.container
    }()

    @MainActor
    static let syncMode: SyncMode = {
        bootstrap.syncMode
    }()

    @MainActor
    static let syncStatusDescription: String = {
        bootstrap.statusDescription
    }()

    @MainActor
    static let bootstrapIssueDescription: String? = {
        bootstrap.bootstrapIssueDescription
    }()
}
