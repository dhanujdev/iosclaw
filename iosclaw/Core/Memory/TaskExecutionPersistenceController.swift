import Foundation
import SwiftData

struct RecentExecutionRun: Identifiable {
    let id: UUID
    let goal: String
    let lifecycleState: AgentLifecycleState
    let lastError: String?
    let updatedAt: Date
    let planJSON: String
}

@MainActor
final class TaskExecutionPersistenceController {
    private let context: ModelContext

    init() {
        self.context = AppModelContainer.shared.mainContext
    }

    init(context: ModelContext) {
        self.context = context
    }

    func startRun(for plan: AgentExecutionPlan, lifecycleState: AgentLifecycleState = .planning) -> UUID {
        let record = TaskExecutionRecord(
            id: plan.id,
            goal: plan.goal,
            planJSON: plan.planJSON,
            lifecycleState: lifecycleState.rawValue,
            createdAt: plan.createdAt,
            updatedAt: .now,
            syncScope: currentSyncScope()
        )
        context.insert(record)
        try? context.save()
        return record.id
    }

    func updateRun(
        id: UUID,
        lifecycleState: AgentLifecycleState,
        planJSON: String,
        lastError: String? = nil
    ) {
        let runID = id
        let descriptor = FetchDescriptor<TaskExecutionRecord>(
            predicate: #Predicate { $0.id == runID }
        )

        guard let record = try? context.fetch(descriptor).first else { return }
        record.lifecycleState = lifecycleState.rawValue
        record.planJSON = planJSON
        record.lastError = lastError
        record.updatedAt = .now
        record.syncScopeRawValue = currentSyncScope().rawValue
        try? context.save()
    }

    func loadRecentRuns(limit: Int = 6) -> [RecentExecutionRun] {
        var descriptor = FetchDescriptor<TaskExecutionRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        let records = (try? context.fetch(descriptor)) ?? []
        return records.map {
            RecentExecutionRun(
                id: $0.id,
                goal: $0.goal,
                lifecycleState: AgentLifecycleState(rawValue: $0.lifecycleState) ?? .failed,
                lastError: $0.lastError,
                updatedAt: $0.updatedAt,
                planJSON: $0.planJSON
            )
        }
    }

    func recoverInterruptedRuns(olderThan staleThreshold: TimeInterval = 120) -> Int {
        let descriptor = FetchDescriptor<TaskExecutionRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .forward)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        let cutoffDate = Date(timeIntervalSinceNow: -staleThreshold)
        let recoverableStates: Set<AgentLifecycleState> = [.observing, .planning, .acting, .evaluating, .waitingForApproval]

        var recoveredCount = 0
        for record in records {
            guard
                let state = AgentLifecycleState(rawValue: record.lifecycleState),
                recoverableStates.contains(state),
                record.updatedAt <= cutoffDate
            else {
                continue
            }

            record.lifecycleState = AgentLifecycleState.failed.rawValue
            if record.lastError == nil || record.lastError?.isEmpty == true {
                record.lastError = "Recovered after app interruption or background expiration."
            }
            record.updatedAt = .now
            record.syncScopeRawValue = currentSyncScope().rawValue
            recoveredCount += 1
        }

        if recoveredCount > 0 {
            try? context.save()
        }

        return recoveredCount
    }

    private func currentSyncScope() -> MemorySyncScope {
        AppModelContainer.syncMode == .cloudKit ? .cloudSynced : .localOnly
    }
}
