import CoreLocation
import Foundation

struct TimelineEntrySnapshot: Hashable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let startTime: Date?
    let endTime: Date?
    let startTimeZoneIdentifier: String
    let endTimeZoneIdentifier: String
    let creationTimeZoneIdentifier: String
    let timeConfidence: TimeConfidence
    let needsReview: Bool
    let kind: LogKind

    let transitType: String
    let transitDistanceMeters: Double?
    let transitDistanceIsApproximate: Bool
    let origin: String
    let destination: String
    let originLocation: TimelineLocationSnapshot?
    let destinationLocation: TimelineLocationSnapshot?

    let visitPlace: String
    let visitSystemImage: PlaceSystemImage
    let visitLocation: TimelineLocationSnapshot?

    let people: [TimelinePersonSnapshot]
    let photoReferences: [PhotoReference]
    let weather: EntryWeather?
    let reviews: [TimelineReviewSnapshot]

    let workoutUUID: UUID?
    let workoutActivityName: String
    let workoutSystemImageName: String
    let workoutMovementKind: WorkoutMovementKind?
    let workoutDistanceMeters: Double?
    let workoutActiveEnergyKilocalories: Double?
    let workoutOrigin: String
    let workoutDestination: String
    let workoutPlace: String
    let workoutOriginLocation: TimelineLocationSnapshot?
    let workoutDestinationLocation: TimelineLocationSnapshot?
    let workoutPlaceLocation: TimelineLocationSnapshot?
    let workoutRouteStart: WorkoutCoordinateSnapshot?
    let workoutRouteEnd: WorkoutCoordinateSnapshot?
    let wakeUpSleepDurationSeconds: Double?

    init(entry: LogEntry) {
        id = entry.id
        createdAt = entry.createdAt
        startTime = entry.startTime
        endTime = entry.endTime
        startTimeZoneIdentifier = entry.startTimeZoneIdentifier
        endTimeZoneIdentifier = entry.endTimeZoneIdentifier
        creationTimeZoneIdentifier = entry.creationTimeZoneIdentifier
        timeConfidence = entry.timeConfidence
        needsReview = entry.needsReview
        kind = entry.kind
        people = entry.people.map {
            TimelinePersonSnapshot(
                id: $0.id,
                name: $0.name,
                contactIdentifier: $0.contactIdentifier
            )
        }
        photoReferences = entry.photoReferences
        weather = entry.weather

        let transit = entry.transitDetails
        transitType = transit?.type ?? "Transit"
        origin = transit?.originPlace?.name
            ?? transit?.originLocation?.timelineAddress
            ?? "Unknown origin"
        destination = transit?.destinationPlace?.name
            ?? transit?.destinationLocation?.timelineAddress
            ?? "Unknown destination"
        originLocation = Self.location(
            place: transit?.originPlace,
            fallbackName: origin,
            location: transit?.originLocation
                ?? transit?.originCandidates.first?.location
        )
        destinationLocation = Self.location(
            place: transit?.destinationPlace,
            fallbackName: destination,
            location: transit?.destinationLocation
                ?? transit?.destinationCandidates.first?.location
        )
        if let storedDistance = transit?.distanceMeters {
            transitDistanceMeters = storedDistance
            transitDistanceIsApproximate = false
        } else if let originLocation,
                  let destinationLocation,
                  originLocation.hasCoordinate,
                  destinationLocation.hasCoordinate {
            transitDistanceMeters = Self.geodesicDistance(
                from: originLocation,
                to: destinationLocation
            )
            transitDistanceIsApproximate = true
        } else {
            transitDistanceMeters = nil
            transitDistanceIsApproximate = false
        }

        let visit = entry.placeVisitDetails
        visitPlace = visit?.place?.name
            ?? visit?.location?.timelineAddress
            ?? "Unknown place"
        visitSystemImage = visit?.place?.systemImage ?? .mappin
        visitLocation = Self.location(
            place: visit?.place,
            fallbackName: visitPlace,
            location: visit?.location ?? visit?.candidates.first?.location
        )

        let workout = entry.workoutDetails
        workoutUUID = workout?.healthKitWorkoutUUID
        workoutActivityName = workout?.activityName ?? "Workout"
        workoutSystemImageName = workout.map {
            WorkoutActivityCatalog.presentation(
                for: $0.activityTypeRawValue
            ).systemImageName
        } ?? "figure.mixed.cardio"
        workoutMovementKind = workout?.movementKind
        workoutDistanceMeters = workout?.distanceMeters
        workoutActiveEnergyKilocalories = workout?.activeEnergyKilocalories
        workoutOrigin = Self.timelineLocationName(
            place: workout?.originPlace,
            location: workout?.originLocation
        )
        workoutDestination = Self.timelineLocationName(
            place: workout?.destinationPlace,
            location: workout?.destinationLocation
        )
        workoutPlace = Self.timelineLocationName(
            place: workout?.place,
            location: workout?.sourceLocation
        )
        workoutOriginLocation = Self.location(
            place: workout?.originPlace,
            fallbackName: workoutOrigin,
            location: workout?.originLocation
        )
        workoutDestinationLocation = Self.location(
            place: workout?.destinationPlace,
            fallbackName: workoutDestination,
            location: workout?.destinationLocation
        )
        workoutPlaceLocation = Self.location(
            place: workout?.place,
            fallbackName: workoutPlace,
            location: workout?.sourceLocation
        )
        workoutRouteStart = workout?.originLocation.map {
            WorkoutCoordinateSnapshot(location: $0)
        } ?? workout?.sourceLocation.map {
            WorkoutCoordinateSnapshot(location: $0)
        }
        workoutRouteEnd = workout?.destinationLocation.map {
            WorkoutCoordinateSnapshot(location: $0)
        }
        wakeUpSleepDurationSeconds = entry.sleepDurationSeconds
        reviews = Self.reviewSnapshots(for: entry)
    }

    init(
        id: UUID = UUID(),
        createdAt: Date,
        startTime: Date?,
        endTime: Date?,
        startTimeZoneIdentifier: String,
        endTimeZoneIdentifier: String,
        creationTimeZoneIdentifier: String,
        timeConfidence: TimeConfidence,
        needsReview: Bool = false,
        kind: LogKind = .transit,
        transitType: String = "Transit",
        origin: String = "Origin",
        destination: String = "Destination",
        visitPlace: String = "Place",
        visitSystemImage: PlaceSystemImage = .mappin,
        workoutActivityName: String = "Workout",
        workoutSystemImageName: String = "figure.mixed.cardio",
        workoutMovementKind: WorkoutMovementKind? = nil,
        workoutDistanceMeters: Double? = nil,
        workoutActiveEnergyKilocalories: Double? = nil,
        workoutOrigin: String = "Origin",
        workoutDestination: String = "Destination",
        workoutPlace: String = "Place",
        workoutRouteStart: WorkoutCoordinateSnapshot? = nil,
        workoutRouteEnd: WorkoutCoordinateSnapshot? = nil,
        wakeUpSleepDurationSeconds: Double? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.startTime = startTime
        self.endTime = endTime
        self.startTimeZoneIdentifier = startTimeZoneIdentifier
        self.endTimeZoneIdentifier = endTimeZoneIdentifier
        self.creationTimeZoneIdentifier = creationTimeZoneIdentifier
        self.timeConfidence = timeConfidence
        self.needsReview = needsReview
        self.kind = kind
        self.transitType = transitType
        transitDistanceMeters = nil
        transitDistanceIsApproximate = false
        self.origin = origin
        self.destination = destination
        originLocation = nil
        destinationLocation = nil
        self.visitPlace = visitPlace
        self.visitSystemImage = visitSystemImage
        visitLocation = nil
        people = []
        photoReferences = []
        weather = nil
        reviews = needsReview
            ? [TimelineReviewSnapshot(target: .time, reason: "Time needs review")]
            : []
        workoutUUID = nil
        self.workoutActivityName = workoutActivityName
        self.workoutSystemImageName = workoutSystemImageName
        self.workoutMovementKind = workoutMovementKind
        self.workoutDistanceMeters = workoutDistanceMeters
        self.workoutActiveEnergyKilocalories = workoutActiveEnergyKilocalories
        self.workoutOrigin = workoutOrigin
        self.workoutDestination = workoutDestination
        self.workoutPlace = workoutPlace
        workoutOriginLocation = nil
        workoutDestinationLocation = nil
        workoutPlaceLocation = nil
        self.workoutRouteStart = workoutRouteStart
        self.workoutRouteEnd = workoutRouteEnd
        self.wakeUpSleepDurationSeconds = wakeUpSleepDurationSeconds
    }

    private static func location(
        place: Place?,
        fallbackName: String,
        candidate: LocationCandidate?
    ) -> TimelineLocationSnapshot? {
        location(
            place: place,
            fallbackName: fallbackName,
            location: candidate?.location
        )
    }

    private static func location(
        place: Place?,
        fallbackName: String,
        location: Location?
    ) -> TimelineLocationSnapshot? {
        guard place != nil || location != nil else { return nil }
        return TimelineLocationSnapshot(
            place: place,
            fallbackName: fallbackName,
            fallbackLocation: location
        )
    }

    private static func geodesicDistance(
        from origin: TimelineLocationSnapshot,
        to destination: TimelineLocationSnapshot
    ) -> Double {
        CLLocation(
            latitude: origin.latitude,
            longitude: origin.longitude
        ).distance(
            from: CLLocation(
                latitude: destination.latitude,
                longitude: destination.longitude
            )
        )
    }

    private static func timelineLocationName(
        place: Place?,
        location: Location?
    ) -> String {
        place?.name
            ?? location?.timelineAddress
            ?? String(localized: "Location unavailable")
    }

    private static func reviewSnapshots(
        for entry: LogEntry
    ) -> [TimelineReviewSnapshot] {
        var result: [TimelineReviewSnapshot] = []
        if let reason = entry.entryKindReviewReason {
            result.append(.init(target: .entryKind, reason: reason))
        }
        switch entry.kind {
        case .transit:
            result.append(contentsOf: entry.transitDetails?.fieldReviews.map {
                TimelineReviewSnapshot(
                    target: target(for: $0.field),
                    reason: $0.reason
                )
            } ?? [])
        case .placeVisit:
            result.append(contentsOf: entry.placeVisitDetails?.fieldReviews.map {
                TimelineReviewSnapshot(
                    target: target(for: $0.field),
                    reason: $0.reason
                )
            } ?? [])
        case .workout:
            result.append(contentsOf: entry.workoutDetails?.fieldReviews.map {
                TimelineReviewSnapshot(
                    target: target(for: $0.field),
                    reason: $0.reason
                )
            } ?? [])
        case .wakeUp:
            break
        }
        return result
    }

    private static func target(
        for field: TransitReviewField
    ) -> TimelineReviewTarget {
        switch field {
        case .transitType: .transitType
        case .origin: .origin
        case .destination: .destination
        case .time: .time
        case .people: .people
        }
    }

    private static func target(
        for field: PlaceVisitReviewField
    ) -> TimelineReviewTarget {
        switch field {
        case .place: .place
        case .time: .time
        case .people: .people
        }
    }

    private static func target(
        for field: WorkoutReviewField
    ) -> TimelineReviewTarget {
        switch field {
        case .place: .place
        case .origin: .origin
        case .destination: .destination
        }
    }
}

extension TimelineEntrySnapshot {
    var workoutWeatherLocation: TimelineLocationSnapshot? {
        workoutMovementKind == .moving
            ? workoutOriginLocation
            : workoutPlaceLocation
    }
}
