import Foundation
import SwiftData

enum SafetyAuditCategory: String {
    case startup
    case cloudSync
    case backgroundExecution
    case agentRun
    case approval
}

enum SafetyAuditSeverity: String {
    case info
    case warning
    case error
}

struct SafetyAuditEntry: Identifiable {
    let id: UUID
    let category: SafetyAuditCategory
    let severity: SafetyAuditSeverity
    let message: String
    let createdAt: Date
}

@MainActor
final class SafetyAuditPersistenceController {
    private let context: ModelContext

    init() {
        self.context = AppModelContainer.shared.mainContext
    }

    init(context: ModelContext) {
        self.context = context
    }

    func record(
        category: SafetyAuditCategory,
        severity: SafetyAuditSeverity,
        message: String
    ) {
        let record = SafetyAuditRecord(
            category: category.rawValue,
            severity: severity.rawValue,
            message: message,
            createdAt: .now
        )
        context.insert(record)
        try? context.save()
    }

    func loadRecentEntries(limit: Int = 10) -> [SafetyAuditEntry] {
        var descriptor = FetchDescriptor<SafetyAuditRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        let records = (try? context.fetch(descriptor)) ?? []
        return records.map {
            SafetyAuditEntry(
                id: $0.id,
                category: SafetyAuditCategory(rawValue: $0.category) ?? .startup,
                severity: SafetyAuditSeverity(rawValue: $0.severity) ?? .info,
                message: $0.message,
                createdAt: $0.createdAt
            )
        }
    }
}
