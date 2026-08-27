import SwiftData

/// `ModelContainer` is safe to hand to a newly-created SwiftData actor, but it
/// does not currently declare `Sendable`. This wrapper is only used to carry
/// the container across the detached actor-construction boundary.
nonisolated struct JournalModelContainerReference: @unchecked Sendable {
    let container: ModelContainer

    init(_ container: ModelContainer) {
        self.container = container
    }
}

/// Retains one persistence actor per container. SwiftData chooses a model
/// actor's context executor when that actor is initialized, so construction is
/// deliberately performed by a detached task instead of a SwiftUI task.
actor JournalPersistenceActors {
    static let shared = JournalPersistenceActors()

    private var maintenanceActors: [
        ObjectIdentifier: JournalBackgroundMaintenance
    ] = [:]
    private var homeFeedActors: [ObjectIdentifier: HomeFeedProjectionStore] = [:]
    private var workoutImportActors: [
        ObjectIdentifier: WorkoutImportPersistence
    ] = [:]

    func maintenance(
        for reference: JournalModelContainerReference
    ) async -> JournalBackgroundMaintenance {
        let identifier = ObjectIdentifier(reference.container)
        if let existing = maintenanceActors[identifier] {
            return existing
        }
        let actor = await Task.detached(priority: .utility) {
            JournalBackgroundMaintenance(
                modelContainer: reference.container
            )
        }.value
        maintenanceActors[identifier] = actor
        return actor
    }

    func homeFeed(
        for reference: JournalModelContainerReference
    ) async -> HomeFeedProjectionStore {
        let identifier = ObjectIdentifier(reference.container)
        if let existing = homeFeedActors[identifier] {
            return existing
        }
        let actor = await Task.detached(priority: .userInitiated) {
            HomeFeedProjectionStore(modelContainer: reference.container)
        }.value
        homeFeedActors[identifier] = actor
        return actor
    }

    func workoutImport(
        for reference: JournalModelContainerReference
    ) async -> WorkoutImportPersistence {
        let identifier = ObjectIdentifier(reference.container)
        if let existing = workoutImportActors[identifier] {
            return existing
        }
        let actor = await Task.detached(priority: .utility) {
            WorkoutImportPersistence(modelContainer: reference.container)
        }.value
        workoutImportActors[identifier] = actor
        return actor
    }
}
