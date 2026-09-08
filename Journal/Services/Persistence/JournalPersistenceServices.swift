import SwiftData

/// All live journal models belong to the container's main context. Independent
/// model actors previously cached separate copies of the same relationship
/// graph while UI actions, imports, and maintenance deleted or replaced it.
/// Serializing each actor separately does not serialize those shared rows.
/// Network and projection work may leave MainActor only with value snapshots.
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
