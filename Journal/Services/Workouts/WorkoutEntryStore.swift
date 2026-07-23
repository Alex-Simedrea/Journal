//
//  WorkoutEntryStore.swift
//  Journal
//

import Foundation
import SwiftData

struct WorkoutResolvedLocations {
    let source: Location?
    let origin: Location?
    let destination: Location?
}

@MainActor
enum WorkoutEntryStore {
    static func upsert(
        snapshot: HealthKitWorkoutSnapshot,
        locations: WorkoutResolvedLocations,
        places: [Place],
        existingEntry: LogEntry?,
        in modelContext: ModelContext
    ) -> LogEntry {
        let creationTimeZoneIdentifier = existingEntry?
            .creationTimeZoneIdentifier ?? TimeZone.current.identifier
        let details = existingEntry?.workoutDetails ?? WorkoutDetails(
            healthKitWorkoutUUID: snapshot.uuid,
            activityTypeRawValue: snapshot.activityTypeRawValue,
            activityName: snapshot.activityName,
            movementKind: snapshot.movementKind
        )
        let entry = existingEntry ?? LogEntry(
            kind: .workout,
            startTime: snapshot.startTime,
            endTime: snapshot.endTime,
            creationTimeZoneIdentifier: creationTimeZoneIdentifier,
            timeConfidence: .explicit,
            needsReview: false
        )

        details.activityTypeRawValue = snapshot.activityTypeRawValue
        details.activityName = snapshot.activityName
        details.movementKind = snapshot.movementKind
        details.distanceMeters = snapshot.distanceMeters
        details.activeEnergyKilocalories = snapshot.activeEnergyKilocalories
        details.routeImportState = snapshot.routeState

        if snapshot.movementKind == .moving {
            updateMovingDetails(
                details,
                snapshot: snapshot,
                locations: locations,
                places: places
            )
        } else {
            updateStaticDetails(
                details,
                snapshot: snapshot,
                locations: locations,
                places: places
            )
        }

        entry.kind = .workout
        entry.startTime = snapshot.startTime
        entry.endTime = snapshot.endTime
        entry.timeConfidence = .explicit
        entry.entryKindReviewReason = nil
        entry.needsReview = !details.fieldReviews.isEmpty
        entry.startTimeZoneIdentifier = startTimeZoneIdentifier(
            details: details,
            metadataIdentifier: snapshot.metadataTimeZoneIdentifier,
            fallbackIdentifier: creationTimeZoneIdentifier
        )
        entry.endTimeZoneIdentifier = endTimeZoneIdentifier(
            details: details,
            metadataIdentifier: snapshot.metadataTimeZoneIdentifier,
            fallbackIdentifier: creationTimeZoneIdentifier
        )
        entry.weather = nil
        entry.endWeather = nil
        entry.workoutDetails = details

        if existingEntry == nil {
            modelContext.insert(entry)
        }
        return entry
    }

    private static func updateMovingDetails(
        _ details: WorkoutDetails,
        snapshot: HealthKitWorkoutSnapshot,
        locations: WorkoutResolvedLocations,
        places: [Place]
    ) {
        details.sourceLocation = nil
        details.place = nil
        details.originLocation = locations.origin
        details.destinationLocation = locations.destination
        details.fieldReviews.removeAll { $0.field == .place }

        if details.originResolutionSource == .automatic {
            details.fieldReviews.removeAll { $0.field == .origin }
            let resolution = resolve(
                coordinate: snapshot.routeStart,
                routeState: snapshot.routeState,
                field: .origin,
                places: places
            )
            details.originPlace = resolution.place
            replaceReview(resolution.review, in: details)
        } else {
            details.fieldReviews.removeAll { $0.field == .origin }
        }

        if details.destinationResolutionSource == .automatic {
            details.fieldReviews.removeAll { $0.field == .destination }
            let resolution = resolve(
                coordinate: snapshot.routeEnd,
                routeState: snapshot.routeState,
                field: .destination,
                places: places
            )
            details.destinationPlace = resolution.place
            replaceReview(resolution.review, in: details)
        } else {
            details.fieldReviews.removeAll { $0.field == .destination }
        }
    }

    private static func updateStaticDetails(
        _ details: WorkoutDetails,
        snapshot: HealthKitWorkoutSnapshot,
        locations: WorkoutResolvedLocations,
        places: [Place]
    ) {
        details.originLocation = nil
        details.destinationLocation = nil
        details.originPlace = nil
        details.destinationPlace = nil
        details.sourceLocation = locations.source
        details.fieldReviews.removeAll {
            $0.field == .origin || $0.field == .destination
        }

        if details.placeResolutionSource == .automatic {
            details.fieldReviews.removeAll { $0.field == .place }
            let resolution = resolve(
                coordinate: snapshot.routeStart,
                routeState: snapshot.routeState,
                field: .place,
                places: places
            )
            details.place = resolution.place
            replaceReview(resolution.review, in: details)
        } else {
            details.fieldReviews.removeAll { $0.field == .place }
        }
    }

    private static func resolve(
        coordinate: WorkoutCoordinateSnapshot?,
        routeState: WorkoutRouteImportState,
        field: WorkoutReviewField,
        places: [Place]
    ) -> (place: Place?, review: WorkoutFieldReview?) {
        guard let coordinate else {
            let reason = routeState == .pending
                ? String(localized: "The HealthKit route is not available yet.")
                : String(localized: "HealthKit did not provide a location for this workout.")
            return (nil, WorkoutFieldReview(field: field, reason: reason))
        }

        switch WorkoutPlaceMatcher.match(coordinate: coordinate, places: places) {
        case .matched(let place):
            return (place, nil)
        case .ambiguous, .unmatched:
            return (nil, nil)
        }
    }

    private static func replaceReview(
        _ review: WorkoutFieldReview?,
        in details: WorkoutDetails
    ) {
        guard let review else { return }
        details.fieldReviews.removeAll { $0.field == review.field }
        details.fieldReviews.append(review)
    }

    private static func startTimeZoneIdentifier(
        details: WorkoutDetails,
        metadataIdentifier: String?,
        fallbackIdentifier: String
    ) -> String {
        if details.movementKind == .moving {
            return details.originLocation?.timeZoneIdentifier
                ?? metadataIdentifier
                ?? fallbackIdentifier
        }
        return details.sourceLocation?.timeZoneIdentifier
            ?? metadataIdentifier
            ?? fallbackIdentifier
    }

    private static func endTimeZoneIdentifier(
        details: WorkoutDetails,
        metadataIdentifier: String?,
        fallbackIdentifier: String
    ) -> String {
        if details.movementKind == .moving {
            return details.destinationLocation?.timeZoneIdentifier
                ?? metadataIdentifier
                ?? fallbackIdentifier
        }
        return details.sourceLocation?.timeZoneIdentifier
            ?? metadataIdentifier
            ?? fallbackIdentifier
    }
}
