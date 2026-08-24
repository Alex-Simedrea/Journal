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
        do {
            try await client.requestAuthorization()
            await synchronize(in: modelContext)
            await startObserving(in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
            print("HealthKit authorization failed: \(error)")
        }
    }

    func synchronize(in modelContext: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let existingReferences = try workoutEntryReferences(in: modelContext)
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
            try apply(
                changeSet,
                wakeUps: wakeUps,
                resolvedSnapshots: resolvedSnapshots,
                in: modelContext
            )
            try WorkoutImportPreferences.save(anchor: changeSet.newAnchor)
            lastSyncDate = .now
            errorMessage = nil
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            print("HealthKit synchronization failed: \(error)")
        }
    }

    private func startObserving(in modelContext: ModelContext) async {
        guard !isObserving else { return }
        isObserving = true
        let cutoff = WorkoutImportPreferences.cutoff()
        await client.startObservingChanges(cutoff: cutoff) { [weak self] in
            guard let self else { return }
            await self.synchronize(in: modelContext)
        }
    }

    private func apply(
        _ changeSet: HealthKitWorkoutChangeSet,
        wakeUps: [HealthKitWakeUpSnapshot],
        resolvedSnapshots: [ResolvedWorkoutImport],
        in modelContext: ModelContext
    ) throws {
        let existingEntries = try workoutEntries(in: modelContext)
        clearResolvedLocationReviews(in: existingEntries)

        var entriesByWorkoutUUID = Dictionary(
            uniqueKeysWithValues: existingEntries.compactMap { entry in
                entry.workoutDetails.map {
                    ($0.healthKitWorkoutUUID, entry)
                }
            }
        )

        for deletedUUID in changeSet.deletedWorkoutUUIDs {
            if let entry = entriesByWorkoutUUID.removeValue(forKey: deletedUUID) {
                modelContext.delete(entry)
            }
            WorkoutImportPreferences.removeExclusion(deletedUUID)
        }

        let places = try modelContext.fetch(
            FetchDescriptor<Place>(sortBy: [SortDescriptor(\Place.createdAt)])
        )
        for resolved in resolvedSnapshots {
            let snapshot = resolved.snapshot
            guard !WorkoutImportPreferences.isExcluded(snapshot.uuid) else {
                continue
            }

            let entry = WorkoutEntryStore.upsert(
                snapshot: snapshot,
                locations: resolved.locations,
                places: places,
                existingEntry: entriesByWorkoutUUID[snapshot.uuid],
                in: modelContext
            )
            entriesByWorkoutUUID[snapshot.uuid] = entry
        }

        try WakeUpEntryStore.synchronize(
            snapshots: wakeUps,
            in: modelContext
        )

        try modelContext.save()
    }

    private func clearResolvedLocationReviews(in entries: [LogEntry]) {
        for entry in entries {
            guard let details = entry.workoutDetails else { continue }
            details.fieldReviews.removeAll { review in
                switch review.field {
                case .place:
                    details.sourceLocation != nil
                case .origin:
                    details.originLocation != nil
                case .destination:
                    details.destinationLocation != nil
                }
            }
            entry.needsReview = !details.fieldReviews.isEmpty
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

    private func workoutEntries(in modelContext: ModelContext) throws -> [LogEntry] {
        try modelContext.fetch(FetchDescriptor<LogEntry>()).filter {
            $0.kind == .workout && $0.workoutDetails != nil
        }
    }

    private func workoutEntryReferences(
        in modelContext: ModelContext
    ) throws -> [WorkoutEntryReference] {
        try workoutEntries(in: modelContext).compactMap { entry in
            guard let details = entry.workoutDetails else { return nil }
            return WorkoutEntryReference(
                workoutUUID: details.healthKitWorkoutUUID,
                movementKind: details.movementKind,
                routeImportState: details.routeImportState
            )
        }
    }
}

private struct WorkoutEntryReference: Sendable {
    let workoutUUID: UUID
    let movementKind: WorkoutMovementKind
    let routeImportState: WorkoutRouteImportState
}

private struct ResolvedWorkoutImport: Sendable {
    let snapshot: HealthKitWorkoutSnapshot
    let locations: WorkoutResolvedLocations
}
