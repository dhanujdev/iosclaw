import Foundation
import SwiftData

@MainActor
final class ChatPersistenceController {
    private let context: ModelContext

    init() {
        self.context = AppModelContainer.shared.mainContext
    }

    init(context: ModelContext) {
        self.context = context
    }

    func loadMessages() -> [ChatMessage] {
        let conversation = primaryConversation()
        let conversationID = conversation.id
        let descriptor = FetchDescriptor<MemoryEntry>(
            predicate: #Predicate { $0.conversationID == conversationID },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        let records = (try? context.fetch(descriptor)) ?? []
        return records.compactMap { record in
            guard let role = Role(rawValue: record.role) else { return nil }
            return ChatMessage(
                id: record.id,
                role: role,
                text: record.text
            )
        }
    }

    func saveOrUpdate(_ message: ChatMessage) {
        let conversation = primaryConversation()
        let messageID = message.id
        let descriptor = FetchDescriptor<MemoryEntry>(
            predicate: #Predicate { $0.id == messageID }
        )

        if let existingRecord = try? context.fetch(descriptor).first {
            existingRecord.role = message.role.rawValue
            existingRecord.text = message.text
            existingRecord.syncScopeRawValue = currentSyncScope().rawValue
        } else {
            let record = MemoryEntry(
                id: message.id,
                conversationID: conversation.id,
                role: message.role.rawValue,
                text: message.text,
                createdAt: .now,
                syncScope: currentSyncScope()
            )
            context.insert(record)
        }

        conversation.updatedAt = .now
        try? context.save()
    }

    func resetThread(with seedMessage: ChatMessage) {
        let conversation = primaryConversation()
        let conversationID = conversation.id
        let descriptor = FetchDescriptor<MemoryEntry>(
            predicate: #Predicate { $0.conversationID == conversationID }
        )

        let records = (try? context.fetch(descriptor)) ?? []
        for record in records {
            context.delete(record)
        }

        let seedRecord = MemoryEntry(
            id: seedMessage.id,
            conversationID: conversation.id,
            role: seedMessage.role.rawValue,
            text: seedMessage.text,
            createdAt: .now,
            syncScope: currentSyncScope()
        )
        context.insert(seedRecord)
        conversation.updatedAt = .now
        try? context.save()
    }

    private func primaryConversation() -> ConversationMemory {
        let descriptor = FetchDescriptor<ConversationMemory>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        if let existingConversation = try? context.fetch(descriptor).first {
            return existingConversation
        }

        let conversation = ConversationMemory(title: "Primary Chat")
        context.insert(conversation)
        try? context.save()
        return conversation
    }

    private func currentSyncScope() -> MemorySyncScope {
        AppModelContainer.syncMode == .cloudKit ? .cloudSynced : .localOnly
    }
}
