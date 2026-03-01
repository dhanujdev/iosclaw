import Foundation
import SwiftData

@MainActor
final class ApprovalPersistenceController {
    private let context: ModelContext

    init() {
        self.context = AppModelContainer.shared.mainContext
    }

    init(context: ModelContext) {
        self.context = context
    }

    func loadPendingApprovals() -> [PendingApprovalRequest] {
        let descriptor = FetchDescriptor<PendingApprovalRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        let records = (try? context.fetch(descriptor)) ?? []
        return records.map {
            PendingApprovalRequest(
                id: $0.id,
                prompt: $0.prompt,
                summary: $0.summary,
                createdAt: $0.createdAt
            )
        }
    }

    func save(_ request: PendingApprovalRequest) {
        let record = PendingApprovalRecord(
            id: request.id,
            prompt: request.prompt,
            summary: request.summary,
            createdAt: request.createdAt
        )
        context.insert(record)
        try? context.save()
    }

    func loadApprovalHistory(limit: Int = 12) -> [ApprovalAuditEntry] {
        var descriptor = FetchDescriptor<ApprovalAuditRecord>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        let records = (try? context.fetch(descriptor)) ?? []
        return records.map {
            ApprovalAuditEntry(
                id: $0.id,
                requestID: $0.requestID,
                prompt: $0.prompt,
                summary: $0.summary,
                decision: ApprovalDecision(rawValue: $0.decisionRawValue) ?? .denied,
                recordedAt: $0.recordedAt
            )
        }
    }

    func recordDecision(for request: PendingApprovalRequest, decision: ApprovalDecision) {
        let record = ApprovalAuditRecord(
            requestID: request.id,
            prompt: request.prompt,
            summary: request.summary,
            decisionRawValue: decision.rawValue,
            recordedAt: .now
        )
        context.insert(record)
        try? context.save()
    }

    func delete(id: UUID) {
        let descriptor = FetchDescriptor<PendingApprovalRecord>(
            predicate: #Predicate { $0.id == id }
        )

        guard let record = try? context.fetch(descriptor).first else { return }
        context.delete(record)
        try? context.save()
    }

    func deleteAll() {
        let descriptor = FetchDescriptor<PendingApprovalRecord>()
        let records = (try? context.fetch(descriptor)) ?? []
        for record in records {
            context.delete(record)
        }
        try? context.save()
    }
}
