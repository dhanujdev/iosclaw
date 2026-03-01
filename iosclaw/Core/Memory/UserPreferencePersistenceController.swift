import Foundation
import SwiftData

@MainActor
final class UserPreferencePersistenceController {
    private let context: ModelContext

    init() {
        self.context = AppModelContainer.shared.mainContext
    }

    init(context: ModelContext) {
        self.context = context
    }

    func value(for key: String) -> String? {
        let preferenceKey = key
        let descriptor = FetchDescriptor<UserPreferenceRecord>(
            predicate: #Predicate { $0.key == preferenceKey }
        )

        return try? context.fetch(descriptor).first?.value
    }

    func upsert(key: String, value: String) {
        let preferenceKey = key
        let descriptor = FetchDescriptor<UserPreferenceRecord>(
            predicate: #Predicate { $0.key == preferenceKey }
        )

        if let existingRecord = try? context.fetch(descriptor).first {
            existingRecord.value = value
            existingRecord.updatedAt = .now
        } else {
            let record = UserPreferenceRecord(
                key: key,
                value: value,
                updatedAt: .now
            )
            context.insert(record)
        }

        try? context.save()
    }
}
