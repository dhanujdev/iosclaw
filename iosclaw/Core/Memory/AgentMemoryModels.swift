import Foundation
import SwiftData

@Model
final class ConversationMemory {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class MemoryEntry {
    @Attribute(.unique) var id: UUID
    var conversationID: UUID
    var role: String
    var text: String
    var summary: String?
    var embeddingKey: String?
    var createdAt: Date
    var syncScopeRawValue: String

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        role: String,
        text: String,
        summary: String? = nil,
        embeddingKey: String? = nil,
        createdAt: Date = .now,
        syncScope: MemorySyncScope = .cloudSynced
    ) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.text = text
        self.summary = summary
        self.embeddingKey = embeddingKey
        self.createdAt = createdAt
        self.syncScopeRawValue = syncScope.rawValue
    }
}

@Model
final class TaskExecutionRecord {
    @Attribute(.unique) var id: UUID
    var goal: String
    var planJSON: String
    var lifecycleState: String
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date
    var syncScopeRawValue: String

    init(
        id: UUID = UUID(),
        goal: String,
        planJSON: String,
        lifecycleState: String,
        lastError: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        syncScope: MemorySyncScope = .localOnly
    ) {
        self.id = id
        self.goal = goal
        self.planJSON = planJSON
        self.lifecycleState = lifecycleState
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncScopeRawValue = syncScope.rawValue
    }
}

@Model
final class UserPreferenceRecord {
    @Attribute(.unique) var key: String
    var value: String
    var updatedAt: Date

    init(key: String, value: String, updatedAt: Date = .now) {
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}

@Model
final class PendingApprovalRecord {
    @Attribute(.unique) var id: UUID
    var prompt: String
    var summary: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        prompt: String,
        summary: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.prompt = prompt
        self.summary = summary
        self.createdAt = createdAt
    }
}

@Model
final class ApprovalAuditRecord {
    @Attribute(.unique) var id: UUID
    var requestID: UUID
    var prompt: String
    var summary: String
    var decisionRawValue: String
    var recordedAt: Date

    init(
        id: UUID = UUID(),
        requestID: UUID,
        prompt: String,
        summary: String,
        decisionRawValue: String,
        recordedAt: Date = .now
    ) {
        self.id = id
        self.requestID = requestID
        self.prompt = prompt
        self.summary = summary
        self.decisionRawValue = decisionRawValue
        self.recordedAt = recordedAt
    }
}

@Model
final class SafetyAuditRecord {
    @Attribute(.unique) var id: UUID
    var category: String
    var severity: String
    var message: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        category: String,
        severity: String,
        message: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.category = category
        self.severity = severity
        self.message = message
        self.createdAt = createdAt
    }
}

enum MemorySyncScope: String, Codable {
    case localOnly
    case cloudSynced
}
