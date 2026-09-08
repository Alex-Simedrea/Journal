import SwiftData

nonisolated enum JournalPersistence {
    /// A failed explicit save must not leave mutations for a later autosave or
    /// unrelated operation to commit. Call from the context's owning actor.
    static func save(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
