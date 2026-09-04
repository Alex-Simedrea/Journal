//
//  WorkoutImportCoordinator.swift
//  Journal
//

import Foundation
import HealthKit
import Observation
import SwiftData

@MainActor
@Observable
final class WorkoutImportCoordinator {
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    var errorMessage: String?

    @ObservationIgnored
    private let client: HealthKitWorkoutClient

    @ObservationIgnored
    private var isObserving = false

    init(client: HealthKitWorkoutClient = .shared) {
        self.client = client
    }

    func start(in modelContext: ModelContext) async {
        await start(modelContainer: modelContext.container)
    }

    func start(modelContainer: ModelContainer) async {
        do {
            try await client.requestAuthorization()
            let persistence = await JournalPersistenceActors.shared
                .workoutImport(
                    for: JournalModelContainerReference(
                        modelContainer
                    )
                )
            await synchronize(using: persistence)
            await startObserving(using: persistence)
        } catch {
            handleImportError(error)
            print("HealthKit authorization failed: \(error)")
        }
    }

    func synchronize(in modelContext: ModelContext) async {
        await synchronize(modelContainer: modelContext.container)
    }

    func synchronize(modelContainer: ModelContainer) async {
        let persistence = await JournalPersistenceActors.shared.workoutImport(
            for: JournalModelContainerReference(modelContainer)
        )
        await synchronize(using: persistence)
    }

    private func synchronize(
        using persistence: WorkoutImportPersistence
    ) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let client = client
            try await Task.detached(priority: .utility) {
                try await WorkoutImportPipeline.synchronize(
                    client: client,
                    persistence: persistence
                )
            }.value
            lastSyncDate = .now
            errorMessage = nil
        } catch {
            handleImportError(error)
            print("HealthKit synchronization failed: \(error)")
        }
    }

    func handleImportError(_ error: Error) {
        let healthError = error as NSError
        // Device locking can interrupt automatic sync. Let the next sync
        // retry without leaving an alert queued for the next foreground.
        if healthError.domain == HKErrorDomain,
           healthError.code == HKError.Code.errorDatabaseInaccessible.rawValue {
            errorMessage = nil
        } else {
            errorMessage = error.localizedDescription
        }
    }

    private func startObserving(
        using persistence: WorkoutImportPersistence
    ) async {
        guard !isObserving else { return }
        isObserving = true
        let cutoff = WorkoutImportPreferences.cutoff()
        await client.startObservingChanges(cutoff: cutoff) { [weak self] in
            guard let self else { return }
            await self.synchronize(using: persistence)
        }
    }

}

nonisolated private enum WorkoutImportPipeline {
    static func synchronize(
        client: HealthKitWorkoutClient,
        persistence: WorkoutImportPersistence
    ) async throws {
        let existingReferences = try await persistence.references()
        if existingReferences.isEmpty, WorkoutImportPreferences.anchor() != nil {
            WorkoutImportPreferences.resetAnchor()
        }

        let cutoff = WorkoutImportPreferences.cutoff()
        async let wakeUps = client.wakeUps(cutoff: cutoff)
        let changeSet = try await client.changes(
            since: WorkoutImportPreferences.anchor(),
            cutoff: cutoff
        )
        let retriedSnapshots = await retryableSnapshots(
            client: client,
            from: existingReferences,
            excluding: Set(changeSet.workouts.map(\.uuid))
                .union(changeSet.deletedWorkoutUUIDs)
        )
        let resolvedSnapshots = await resolvedSnapshots(
            changeSet.workouts + retriedSnapshots
        )
        try await persistence.apply(
            changeSet,
            wakeUps: try await wakeUps,
            resolvedSnapshots: resolvedSnapshots
        )
        try WorkoutImportPreferences.save(anchor: changeSet.newAnchor)
    }

    private static func retryableSnapshots(
        client: HealthKitWorkoutClient,
        from references: [WorkoutEntryReference],
        excluding excludedUUIDs: Set<UUID>
    ) async -> [HealthKitWorkoutSnapshot] {
        var snapshots: [HealthKitWorkoutSnapshot] = []
        for reference in references {
            let currentMovementKind = WorkoutActivityCatalog.movementKind(
                for: reference.activityTypeRawValue
            )
            let needsMovementMigration =
                reference.movementKind != currentMovementKind
            let needsRouteRetry = reference.movementKind == .moving
                && reference.routeImportState != .available
            guard needsMovementMigration || needsRouteRetry,
                  !excludedUUIDs.contains(reference.workoutUUID),
                  !WorkoutImportPreferences.isExcluded(reference.workoutUUID)
            else {
                continue
            }

            do {
                snapshots.append(
                    try await client.currentSnapshot(
                        for: reference.workoutUUID
                    )
                )
            } catch {
                print("HealthKit delayed route retry failed: \(error)")
            }
        }
        return snapshots
    }

    private static func resolvedLocations(
        for snapshot: HealthKitWorkoutSnapshot
    ) async -> WorkoutResolvedLocations {
        if snapshot.movementKind == .moving {
            return WorkoutResolvedLocations(
                source: nil,
                origin: await resolvedLocation(snapshot.routeStart),
                destination: await resolvedLocation(snapshot.routeEnd)
            )
        }

        return WorkoutResolvedLocations(
            source: await resolvedLocation(snapshot.routeStart),
            origin: nil,
            destination: nil
        )
    }

    private static func resolvedSnapshots(
        _ snapshots: [HealthKitWorkoutSnapshot]
    ) async -> [ResolvedWorkoutImport] {
        var result: [ResolvedWorkoutImport] = []
        result.reserveCapacity(snapshots.count)
        for snapshot in snapshots {
            result.append(
                ResolvedWorkoutImport(
                    snapshot: snapshot,
                    locations: await resolvedLocations(for: snapshot)
                )
            )
        }
        return result
    }

    private static func resolvedLocation(
        _ coordinate: WorkoutCoordinateSnapshot?
    ) async -> Location? {
        guard let coordinate else { return nil }
        return await LocationService.resolvedLocation(at: coordinate.coordinate)
    }
}
