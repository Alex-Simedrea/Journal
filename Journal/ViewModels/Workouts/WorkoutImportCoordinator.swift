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
            let existingEntries = try workoutEntries(in: modelContext)
            if existingEntries.isEmpty, WorkoutImportPreferences.anchor() != nil {
                WorkoutImportPreferences.resetAnchor()
            }

            let cutoff = WorkoutImportPreferences.cutoff()
            let changeSet = try await client.changes(
                since: WorkoutImportPreferences.anchor(),
                cutoff: cutoff
            )
            let wakeUps = try await client.wakeUps(cutoff: cutoff)
            let retriedSnapshots = await retryableSnapshots(
                from: existingEntries,
                excluding: Set(changeSet.workouts.map(\.uuid))
                    .union(changeSet.deletedWorkoutUUIDs)
            )
            try await apply(
                changeSet,
                wakeUps: wakeUps,
                retriedSnapshots: retriedSnapshots,
                existingEntries: existingEntries,
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
        retriedSnapshots: [HealthKitWorkoutSnapshot],
        existingEntries: [LogEntry],
        in modelContext: ModelContext
    ) async throws {
        await refreshStoredLocationMetadata(in: existingEntries)
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
        for snapshot in changeSet.workouts + retriedSnapshots {
            guard !WorkoutImportPreferences.isExcluded(snapshot.uuid) else {
                continue
            }

            let locations = await resolvedLocations(for: snapshot)
            let entry = WorkoutEntryStore.upsert(
                snapshot: snapshot,
                locations: locations,
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

    private func refreshStoredLocationMetadata(
        in entries: [LogEntry]
    ) async {
        for entry in entries {
            guard let details = entry.workoutDetails else { continue }
            if details.movementKind == .moving {
                details.originLocation = await enriched(
                    details.originLocation
                )
                details.destinationLocation = await enriched(
                    details.destinationLocation
                )
            } else {
                details.sourceLocation = await enriched(
                    details.sourceLocation
                )
            }
        }
    }

    private func enriched(_ location: Location?) async -> Location? {
        guard let location else { return nil }
        guard location.compactAddress == nil
                || location.formattedAddress == nil
                || location.timeZoneIdentifier == nil else {
            return location
        }

        let resolved = await LocationService.shared.location(
            at: location.coordinate
        )
        return Location(
            latitude: location.latitude,
            longitude: location.longitude,
            formattedAddress: resolved.formattedAddress
                ?? location.formattedAddress,
            compactAddress: resolved.compactAddress
                ?? location.compactAddress,
            timeZoneIdentifier: resolved.timeZoneIdentifier
                ?? location.timeZoneIdentifier
        )
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
        from entries: [LogEntry],
        excluding excludedUUIDs: Set<UUID>
    ) async -> [HealthKitWorkoutSnapshot] {
        var snapshots: [HealthKitWorkoutSnapshot] = []
        for entry in entries {
            guard let details = entry.workoutDetails,
                  details.movementKind == .moving,
                  details.routeImportState != .available,
                  !excludedUUIDs.contains(details.healthKitWorkoutUUID),
                  !WorkoutImportPreferences.isExcluded(details.healthKitWorkoutUUID)
            else {
                continue
            }

            do {
                snapshots.append(
                    try await client.currentSnapshot(
                        for: details.healthKitWorkoutUUID
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
}
