//
//  WorkoutEntryStore.swift
//  Journal
//

import Foundation
import SwiftData

nonisolated struct WorkoutResolvedLocations: Sendable {
    let source: Location?
    let origin: Location?
    let destination: Location?
}

nonisolated enum WorkoutEntryStore {
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
        let previousStartWeatherRequest = existingEntry.flatMap {
            EntryWeatherService.request(for: $0, endpoint: .start)
        }
        let previousEndWeatherRequest = existingEntry.flatMap {
            EntryWeatherService.request(for: $0, endpoint: .end)
        }

        if details.activityTypeRawValue != snapshot.activityTypeRawValue {
            details.activityTypeRawValue = snapshot.activityTypeRawValue
        }
        if details.activityName != snapshot.activityName {
            details.activityName = snapshot.activityName
        }
        if details.movementKind != snapshot.movementKind {
            details.movementKind = snapshot.movementKind
        }
        if details.distanceMeters != snapshot.distanceMeters {
            details.distanceMeters = snapshot.distanceMeters
        }
        if details.activeEnergyKilocalories
            != snapshot.activeEnergyKilocalories {
            details.activeEnergyKilocalories = snapshot.activeEnergyKilocalories
        }
        if details.routeImportState != snapshot.routeState {
            details.routeImportState = snapshot.routeState
        }

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

        if entry.kind != .workout { entry.kind = .workout }
        if entry.startTime != snapshot.startTime {
            entry.startTime = snapshot.startTime
        }
        if entry.endTime != snapshot.endTime {
            entry.endTime = snapshot.endTime
        }
        if entry.timeConfidence != .explicit {
            entry.timeConfidence = .explicit
        }
        if entry.entryKindReviewReason != nil {
            entry.entryKindReviewReason = nil
        }
        let needsReview = !details.fieldReviews.isEmpty
        if entry.needsReview != needsReview {
            entry.needsReview = needsReview
        }
        let startZone = startTimeZoneIdentifier(
            details: details,
            metadataIdentifier: snapshot.metadataTimeZoneIdentifier,
            fallbackIdentifier: creationTimeZoneIdentifier
        )
        if entry.startTimeZoneIdentifier != startZone {
            entry.startTimeZoneIdentifier = startZone
        }
        let endZone = endTimeZoneIdentifier(
            details: details,
            metadataIdentifier: snapshot.metadataTimeZoneIdentifier,
            fallbackIdentifier: creationTimeZoneIdentifier
        )
        if entry.endTimeZoneIdentifier != endZone {
            entry.endTimeZoneIdentifier = endZone
        }
        if entry.workoutDetails == nil { entry.workoutDetails = details }

        if existingEntry != nil,
           previousStartWeatherRequest
            != EntryWeatherService.request(for: entry, endpoint: .start),
           entry.weather != nil {
            entry.weather = nil
        }
        if existingEntry != nil,
           previousEndWeatherRequest
            != EntryWeatherService.request(for: entry, endpoint: .end),
           entry.endWeather != nil {
            entry.endWeather = nil
        }

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
        if details.sourceLocation != nil { details.sourceLocation = nil }
        if details.place != nil { details.place = nil }
        if details.originLocation != locations.origin {
            details.originLocation = locations.origin
        }
        if details.destinationLocation != locations.destination {
            details.destinationLocation = locations.destination
        }
        removeReviews([.place], from: details)

        if details.originResolutionSource == .automatic {
            removeReviews([.origin], from: details)
            let resolution = resolve(
                coordinate: snapshot.routeStart,
                routeState: snapshot.routeState,
                field: .origin,
                places: places
            )
            if details.originPlace?.id != resolution.place?.id {
                details.originPlace = resolution.place
            }
            replaceReview(resolution.review, in: details)
        } else {
            removeReviews([.origin], from: details)
        }

        if details.destinationResolutionSource == .automatic {
            removeReviews([.destination], from: details)
            let resolution = resolve(
                coordinate: snapshot.routeEnd,
                routeState: snapshot.routeState,
                field: .destination,
                places: places
            )
            if details.destinationPlace?.id != resolution.place?.id {
                details.destinationPlace = resolution.place
            }
            replaceReview(resolution.review, in: details)
        } else {
            removeReviews([.destination], from: details)
        }
    }

    private static func updateStaticDetails(
        _ details: WorkoutDetails,
        snapshot: HealthKitWorkoutSnapshot,
        locations: WorkoutResolvedLocations,
        places: [Place]
    ) {
        if details.originLocation != nil { details.originLocation = nil }
        if details.destinationLocation != nil {
            details.destinationLocation = nil
        }
        if details.originPlace != nil { details.originPlace = nil }
        if details.destinationPlace != nil { details.destinationPlace = nil }
        if details.sourceLocation != locations.source {
            details.sourceLocation = locations.source
        }
        removeReviews([.origin, .destination], from: details)

        if details.placeResolutionSource == .automatic {
            removeReviews([.place], from: details)
            let resolution = resolve(
                coordinate: snapshot.routeStart,
                routeState: snapshot.routeState,
                field: .place,
                places: places
            )
            if details.place?.id != resolution.place?.id {
                details.place = resolution.place
            }
            replaceReview(resolution.review, in: details)
        } else {
            removeReviews([.place], from: details)
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
        var reviews = details.fieldReviews.filter { $0.field != review.field }
        reviews.append(review)
        if details.fieldReviews != reviews {
            details.fieldReviews = reviews
        }
    }

    private static func removeReviews(
        _ fields: Set<WorkoutReviewField>,
        from details: WorkoutDetails
    ) {
        let reviews = details.fieldReviews
        let filtered = reviews.filter { !fields.contains($0.field) }
        if filtered != reviews { details.fieldReviews = filtered }
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
