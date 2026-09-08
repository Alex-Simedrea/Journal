import SwiftData

/// Retains one background persistence service per container.
///
/// Live journal models that the UI edits belong to the container's main
/// context. These services never hand models out: they fetch, work on value
/// snapshots, re-fetch by ID after every suspension point, and save
/// immediately, so heavy fetching, projection, and enrichment stay off the
/// main thread without a second long-lived copy of the relationship graph.
///
/// Each service owns a serial dispatch queue as its actor executor, so the
/// construction thread does not matter and no call runs on the main thread.
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
        let service = JournalBackgroundMaintenance(modelContainer: container)
        maintenanceServices[identifier] = service
        return service
    }

    func homeFeed(
        for container: ModelContainer
    ) async -> HomeFeedProjectionStore {
        let identifier = ObjectIdentifier(container)
        if let existing = homeFeedServices[identifier] { return existing }
        let service = HomeFeedProjectionStore(modelContainer: container)
        homeFeedServices[identifier] = service
        return service
    }

    func workoutImport(
        for container: ModelContainer
    ) async -> WorkoutImportPersistence {
        let identifier = ObjectIdentifier(container)
        if let existing = workoutImportServices[identifier] { return existing }
        let service = WorkoutImportPersistence(modelContainer: container)
        workoutImportServices[identifier] = service
        return service
    }
}
