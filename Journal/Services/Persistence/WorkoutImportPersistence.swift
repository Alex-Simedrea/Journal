import Foundation
import SwiftData

nonisolated struct WorkoutEntryReference: Sendable {
    let workoutUUID: UUID
    let movementKind: WorkoutMovementKind
    let routeImportState: WorkoutRouteImportState
}

nonisolated struct ResolvedWorkoutImport: Sendable {
    let snapshot: HealthKitWorkoutSnapshot
    let locations: WorkoutResolvedLocations
}

@ModelActor
actor WorkoutImportPersistence {
    func references() throws -> [WorkoutEntryReference] {
        try workoutEntries().compactMap { entry in
            guard let details = entry.workoutDetails else { return nil }
            return WorkoutEntryReference(
                workoutUUID: details.healthKitWorkoutUUID,
                movementKind: details.movementKind,
                routeImportState: details.routeImportState
            )
        }
    }

    func apply(
        _ changeSet: HealthKitWorkoutChangeSet,
        wakeUps: [HealthKitWakeUpSnapshot],
        resolvedSnapshots: [ResolvedWorkoutImport]
    ) async throws {
        do {
            let existingEntries = try workoutEntries()
            clearResolvedLocationReviews(in: existingEntries)

            var entriesByWorkoutUUID = Dictionary(
                uniqueKeysWithValues: existingEntries.compactMap { entry in
                    entry.workoutDetails.map {
                        ($0.healthKitWorkoutUUID, entry)
                    }
                }
            )

            for deletedUUID in changeSet.deletedWorkoutUUIDs {
                if let entry = entriesByWorkoutUUID.removeValue(
                    forKey: deletedUUID
                ) {
                    modelContext.delete(entry)
                }
                WorkoutImportPreferences.removeExclusion(deletedUUID)
            }

            let places = try modelContext.fetch(
                FetchDescriptor<Place>(
                    sortBy: [SortDescriptor(\Place.createdAt)]
                )
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
            await TimelineDataChange.post(.structure)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func workoutEntries() throws -> [LogEntry] {
        try modelContext.fetch(FetchDescriptor<LogEntry>()).filter {
            $0.kind == .workout && $0.workoutDetails != nil
        }
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
}
