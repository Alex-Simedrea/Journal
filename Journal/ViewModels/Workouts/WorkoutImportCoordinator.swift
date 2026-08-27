//
//  WorkoutImportCoordinator.swift
//  Journal
//

import Foundation
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
            errorMessage = error.localizedDescription
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
            let existingReferences = try await persistence.references()
            if existingReferences.isEmpty, WorkoutImportPreferences.anchor() != nil {
                WorkoutImportPreferences.resetAnchor()
            }

            let cutoff = WorkoutImportPreferences.cutoff()
            let changeSet = try await client.changes(
                since: WorkoutImportPreferences.anchor(),
                cutoff: cutoff
            )
            let wakeUps = try await client.wakeUps(cutoff: cutoff)
            let retriedSnapshots = await retryableSnapshots(
                from: existingReferences,
                excluding: Set(changeSet.workouts.map(\.uuid))
                    .union(changeSet.deletedWorkoutUUIDs)
            )
            let resolvedSnapshots = await resolvedSnapshots(
                changeSet.workouts + retriedSnapshots
            )
            try await persistence.apply(
                changeSet,
                wakeUps: wakeUps,
                resolvedSnapshots: resolvedSnapshots
            )
            try WorkoutImportPreferences.save(anchor: changeSet.newAnchor)
            lastSyncDate = .now
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            print("HealthKit synchronization failed: \(error)")
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

    private func retryableSnapshots(
        from references: [WorkoutEntryReference],
        excluding excludedUUIDs: Set<UUID>
    ) async -> [HealthKitWorkoutSnapshot] {
        var snapshots: [HealthKitWorkoutSnapshot] = []
        for reference in references {
            guard reference.movementKind == .moving,
                  reference.routeImportState != .available,
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

    private func resolvedLocations(
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

    private func resolvedSnapshots(
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

    private func resolvedLocation(
        _ coordinate: WorkoutCoordinateSnapshot?
    ) async -> Location? {
        guard let coordinate else { return nil }
        return await LocationService.shared.location(at: coordinate.coordinate)
    }

}
