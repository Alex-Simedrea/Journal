import SwiftData

/// `ModelContainer` is safe to hand to a newly created SwiftData actor, but it
/// does not currently declare `Sendable`. This wrapper only carries the
/// container across the detached actor-construction boundary.
nonisolated private struct JournalModelContainerBox: @unchecked Sendable {
    let container: ModelContainer
}

/// Retains one background persistence service per container.
///
/// Live journal models that the UI edits belong to the container's main
/// context. These services never hand models out: they fetch, work on value
/// snapshots, re-fetch by ID after every suspension point, and save
/// immediately, so heavy fetching, projection, and enrichment stay off the
/// main thread without a second long-lived copy of the relationship graph.
///
/// SwiftData chooses a model actor's executor when the actor is initialized,
/// so construction is deliberately performed by a detached task instead of a
/// main-actor SwiftUI task.
@MainActor
final class JournalPersistenceServices {
    static let shared = JournalPersistenceServices()

    private var maintenanceServices: [ObjectIdentifier: JournalBackgroundMaintenance] = [:]
    private var homeFeedServices: [ObjectIdentifier: HomeFeedProjectionStore] = [:]
    private var workoutImportServices: [ObjectIdentifier: WorkoutImportPersistence] = [:]

    func maintenance(
        for container: ModelContainer
    ) async -> JournalBackgroundMaintenance {
        let identifier = ObjectIdentifier(container)
        if let existing = maintenanceServices[identifier] { return existing }
        let box = JournalModelContainerBox(container: container)
        let service = await Task.detached(priority: .utility) {
            JournalBackgroundMaintenance(modelContainer: box.container)
        }.value
        if let existing = maintenanceServices[identifier] { return existing }
        maintenanceServices[identifier] = service
        return service
    }

    func homeFeed(
        for container: ModelContainer
    ) async -> HomeFeedProjectionStore {
        let identifier = ObjectIdentifier(container)
        if let existing = homeFeedServices[identifier] { return existing }
        let box = JournalModelContainerBox(container: container)
        let service = await Task.detached(priority: .userInitiated) {
            HomeFeedProjectionStore(modelContainer: box.container)
        }.value
        if let existing = homeFeedServices[identifier] { return existing }
        homeFeedServices[identifier] = service
        return service
    }

    func workoutImport(
        for container: ModelContainer
    ) async -> WorkoutImportPersistence {
        let identifier = ObjectIdentifier(container)
        if let existing = workoutImportServices[identifier] { return existing }
        let box = JournalModelContainerBox(container: container)
        let service = await Task.detached(priority: .utility) {
            WorkoutImportPersistence(modelContainer: box.container)
        }.value
        if let existing = workoutImportServices[identifier] { return existing }
        workoutImportServices[identifier] = service
        return service
    }
}
