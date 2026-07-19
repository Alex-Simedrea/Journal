//
//  TimelineProjection.swift
//  Journal
//

import CoreLocation
import Foundation

struct TimelineDayKey: Hashable, Identifiable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    var id: String { "\(year)-\(month)-\(day)" }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 1
        month = components.month ?? 1
        day = components.day ?? 1
    }

    static func today(
        now: Date = .now,
        timeZone: TimeZone = .current
    ) -> TimelineDayKey {
        TimelineDayKey(date: now, timeZone: timeZone)
    }

    func addingDays(_ value: Int) -> TimelineDayKey {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              let movedDate = calendar.date(byAdding: .day, value: value, to: date) else {
            return self
        }
        return TimelineDayKey(date: movedDate, timeZone: calendar.timeZone)
    }

    func dateInterval(in timeZone: TimeZone) -> DateInterval? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let nextDay = addingDays(1)
        let startComponents = DateComponents(year: year, month: month, day: day)
        let endComponents = DateComponents(
            year: nextDay.year,
            month: nextDay.month,
            day: nextDay.day
        )
        guard let start = calendar.date(from: startComponents),
              let end = calendar.date(from: endComponents) else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    func displayDate(in timeZone: TimeZone = .current) -> Date {
        dateInterval(in: timeZone)?.start ?? .now
    }

    var conservativeQueryWindow: DateInterval {
        let earliestZone = TimeZone(secondsFromGMT: 14 * 60 * 60) ?? .gmt
        let latestZone = TimeZone(secondsFromGMT: -12 * 60 * 60) ?? .gmt
        let earliestStart = dateInterval(in: earliestZone)?.start ?? .distantPast
        let latestEnd = dateInterval(in: latestZone)?.end ?? .distantFuture
        return DateInterval(start: earliestStart, end: latestEnd)
    }
}

enum TimelineOccurrenceRole: String, Hashable, Sendable {
    case intervalDay
    case crossZoneArrival
    case unresolvedReview
}

struct TimelineOccurrenceID: Hashable, Sendable {
    let entryID: UUID
    let day: TimelineDayKey
    let timeZoneIdentifier: String
    let role: TimelineOccurrenceRole
}

struct TimelineLocationSnapshot: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let systemImage: PlaceSystemImage

    init(
        place: Place?,
        fallbackName: String,
        fallbackLocation: Location?,
        fallbackSystemImage: PlaceSystemImage = .mappin
    ) {
        let location = place?.location ?? fallbackLocation
        name = place?.name ?? fallbackName
        latitude = location?.latitude ?? 0
        longitude = location?.longitude ?? 0
        systemImage = place?.systemImage ?? fallbackSystemImage
        if let place {
            id = place.id.uuidString
        } else if let location {
            id = "\(fallbackName)-\(location.latitude)-\(location.longitude)"
        } else {
            id = "unresolved-\(fallbackName)"
        }
    }

    var hasCoordinate: Bool {
        (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
            && !(latitude == 0 && longitude == 0)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct TimelinePersonSnapshot: Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let contactIdentifier: String?
}

enum TimelineReviewTarget: String, Hashable, Sendable {
    case entryKind
    case transitType
    case origin
    case destination
    case place
    case time
    case people
}

struct TimelineReviewSnapshot: Hashable, Identifiable, Sendable {
    let target: TimelineReviewTarget
    let reason: String

    var id: String { "\(target.rawValue)-\(reason)" }
}

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
            ?? transit?.originRawText
            ?? "Unknown origin"
        destination = transit?.destinationPlace?.name
            ?? transit?.destinationRawText
            ?? "Unknown destination"
        originLocation = Self.location(
            place: transit?.originPlace,
            fallbackName: origin,
            candidate: transit?.originCandidates.first
        )
        destinationLocation = Self.location(
            place: transit?.destinationPlace,
            fallbackName: destination,
            candidate: transit?.destinationCandidates.first
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
            ?? visit?.placeRawText
            ?? "Unknown place"
        visitSystemImage = visit?.place?.systemImage ?? .mappin
        visitLocation = Self.location(
            place: visit?.place,
            fallbackName: visitPlace,
            candidate: visit?.candidates.first
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
        workoutOrigin = WorkoutLocationPresentation.name(
            place: workout?.originPlace,
            location: workout?.originLocation
        )
        workoutDestination = WorkoutLocationPresentation.name(
            place: workout?.destinationPlace,
            location: workout?.destinationLocation
        )
        workoutPlace = WorkoutLocationPresentation.name(
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
        workoutRouteEnd: WorkoutCoordinateSnapshot? = nil
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
    }

    private static func location(
        place: Place?,
        fallbackName: String,
        candidate: PlaceCandidate?
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

struct TimelineOccurrence: Hashable, Identifiable, Sendable {
    let id: TimelineOccurrenceID
    let entryID: UUID
    let role: TimelineOccurrenceRole
    let timeZoneIdentifier: String
    let endTimeZoneIdentifier: String
    let sortTime: Date
    let visibleStartTime: Date?
    let visibleEndTime: Date?
    let startTime: Date?
    let endTime: Date?
    let needsReview: Bool
    let kind: LogKind
    let snapshot: TimelineEntrySnapshot

    var changesTimeZone: Bool {
        timeZoneIdentifier != endTimeZoneIdentifier
            && visibleEndTime == endTime
    }

    var reviewsTime: Bool {
        snapshot.reviews.contains { $0.target == .time }
    }

    var transitType: String { snapshot.transitType }
    var origin: String { snapshot.origin }
    var destination: String { snapshot.destination }
    var visitPlace: String { snapshot.visitPlace }
    var visitSystemImage: PlaceSystemImage { snapshot.visitSystemImage }
    var workoutActivityName: String { snapshot.workoutActivityName }
    var workoutSystemImageName: String { snapshot.workoutSystemImageName }
    var workoutMovementKind: WorkoutMovementKind? { snapshot.workoutMovementKind }
    var workoutDistanceMeters: Double? { snapshot.workoutDistanceMeters }
    var workoutActiveEnergyKilocalories: Double? {
        snapshot.workoutActiveEnergyKilocalories
    }
    var workoutOrigin: String { snapshot.workoutOrigin }
    var workoutDestination: String { snapshot.workoutDestination }
    var workoutPlace: String { snapshot.workoutPlace }
}

enum TimelinePreviousRelationship: Hashable, Sendable {
    case first
    case contiguous
    case gap(TimeInterval)
    case overlap
}

struct TimelineRow: Hashable, Identifiable, Sendable {
    let occurrence: TimelineOccurrence
    let relationshipToPrevious: TimelinePreviousRelationship

    var id: TimelineOccurrenceID { occurrence.id }
}

struct TimelineTimeZoneChange: Hashable, Identifiable, Sendable {
    let id: TimelineOccurrenceID
    let fromTimeZoneIdentifier: String
    let toTimeZoneIdentifier: String
    let date: Date
}

enum TimelineListItem: Hashable, Identifiable, Sendable {
    case occurrence(TimelineOccurrence)
    case timeZoneChange(TimelineTimeZoneChange)

    var id: String {
        switch self {
        case .occurrence(let occurrence):
            "occurrence-\(occurrence.id.entryID)-\(occurrence.id.day.id)-\(occurrence.id.timeZoneIdentifier)-\(occurrence.id.role.rawValue)"
        case .timeZoneChange(let change):
            "zone-change-\(change.id.entryID)-\(change.id.day.id)-\(change.fromTimeZoneIdentifier)-\(change.toTimeZoneIdentifier)"
        }
    }
}

struct TimelineProjection: Sendable {
    let occurrences: [TimelineOccurrence]
    let rows: [TimelineRow]
    let reviewOccurrences: [TimelineOccurrence]
    let listItems: [TimelineListItem]

    static func project(
        entries: [TimelineEntrySnapshot],
        for day: TimelineDayKey
    ) -> TimelineProjection {
        var occurrences: [TimelineOccurrence] = []
        var reviews: [TimelineOccurrence] = []

        for entry in entries {
            guard let startTime = entry.startTime,
                  let endTime = entry.endTime,
                  endTime > startTime else {
                if let review = unresolvedOccurrence(for: entry, on: day) {
                    reviews.append(review)
                }
                continue
            }

            let startZone = timeZone(
                identifier: entry.startTimeZoneIdentifier,
                fallbackIdentifier: entry.creationTimeZoneIdentifier
            )
            let endZone = timeZone(
                identifier: entry.endTimeZoneIdentifier,
                fallbackIdentifier: entry.creationTimeZoneIdentifier
            )
            let startDayInterval = day.dateInterval(in: startZone)
            let overlapsStartZoneDay = startDayInterval.map {
                startTime < $0.end && endTime > $0.start
            } ?? false
            let isCrossZoneArrivalDay = (
                entry.kind == .transit || entry.workoutMovementKind == .moving
            ) && startZone.identifier != endZone.identifier
                && TimelineDayKey(date: endTime, timeZone: endZone) == day

            guard overlapsStartZoneDay || isCrossZoneArrivalDay else { continue }

            let visibleStart: Date?
            let visibleEnd: Date?
            let role: TimelineOccurrenceRole
            if overlapsStartZoneDay, let interval = startDayInterval {
                visibleStart = max(startTime, interval.start)
                visibleEnd = isCrossZoneArrivalDay
                    ? endTime
                    : min(endTime, interval.end)
                role = .intervalDay
            } else {
                visibleStart = nil
                visibleEnd = endTime
                role = .crossZoneArrival
            }
            occurrences.append(
                occurrence(
                    entry: entry,
                    day: day,
                    role: role,
                    timeZoneIdentifier: startZone.identifier,
                    endTimeZoneIdentifier: endZone.identifier,
                    sortTime: visibleStart ?? endTime,
                    visibleStartTime: visibleStart,
                    visibleEndTime: visibleEnd
                )
            )
        }

        occurrences.sort(by: occurrenceOrder)
        reviews.sort(by: occurrenceOrder)

        var previous: TimelineOccurrence?
        let rows = occurrences.map { occurrence in
            let relationship: TimelinePreviousRelationship
            if let previous,
               let previousEnd = previous.visibleEndTime,
               let start = occurrence.visibleStartTime {
                if boundariesAreContiguous(previousEnd, start) {
                    relationship = .contiguous
                } else if previousEnd < start {
                    relationship = .gap(start.timeIntervalSince(previousEnd))
                } else {
                    relationship = .overlap
                }
            } else {
                relationship = .first
            }
            previous = occurrence
            return TimelineRow(
                occurrence: occurrence,
                relationshipToPrevious: relationship
            )
        }

        return TimelineProjection(
            occurrences: occurrences,
            rows: rows,
            reviewOccurrences: reviews,
            listItems: occurrences.map(TimelineListItem.occurrence)
        )
    }

    private static func boundariesAreContiguous(
        _ previousEnd: Date,
        _ nextStart: Date
    ) -> Bool {
        return floor(previousEnd.timeIntervalSinceReferenceDate / 60)
            == floor(nextStart.timeIntervalSinceReferenceDate / 60)
    }

    private static func unresolvedOccurrence(
        for entry: TimelineEntrySnapshot,
        on day: TimelineDayKey
    ) -> TimelineOccurrence? {
        let creationZone = timeZone(
            identifier: entry.creationTimeZoneIdentifier,
            fallbackIdentifier: TimeZone.current.identifier
        )
        guard TimelineDayKey(date: entry.createdAt, timeZone: creationZone) == day else {
            return nil
        }
        return occurrence(
            entry: entry,
            day: day,
            role: .unresolvedReview,
            timeZoneIdentifier: creationZone.identifier,
            endTimeZoneIdentifier: creationZone.identifier,
            sortTime: entry.startTime ?? entry.endTime ?? entry.createdAt,
            visibleStartTime: entry.startTime,
            visibleEndTime: entry.endTime
        )
    }

    private static func occurrence(
        entry: TimelineEntrySnapshot,
        day: TimelineDayKey,
        role: TimelineOccurrenceRole,
        timeZoneIdentifier: String,
        endTimeZoneIdentifier: String,
        sortTime: Date,
        visibleStartTime: Date?,
        visibleEndTime: Date?
    ) -> TimelineOccurrence {
        TimelineOccurrence(
            id: TimelineOccurrenceID(
                entryID: entry.id,
                day: day,
                timeZoneIdentifier: timeZoneIdentifier,
                role: role
            ),
            entryID: entry.id,
            role: role,
            timeZoneIdentifier: timeZoneIdentifier,
            endTimeZoneIdentifier: endTimeZoneIdentifier,
            sortTime: sortTime,
            visibleStartTime: visibleStartTime,
            visibleEndTime: visibleEndTime,
            startTime: entry.startTime,
            endTime: entry.endTime,
            needsReview: entry.needsReview,
            kind: entry.kind,
            snapshot: entry
        )
    }

    nonisolated private static func occurrenceOrder(
        _ lhs: TimelineOccurrence,
        _ rhs: TimelineOccurrence
    ) -> Bool {
        if lhs.sortTime != rhs.sortTime {
            return lhs.sortTime < rhs.sortTime
        }
        if lhs.role != rhs.role {
            return lhs.role.rawValue < rhs.role.rawValue
        }
        return lhs.entryID.uuidString < rhs.entryID.uuidString
    }

    private static func timeZone(
        identifier: String,
        fallbackIdentifier: String
    ) -> TimeZone {
        TimeZone(identifier: identifier)
            ?? TimeZone(identifier: fallbackIdentifier)
            ?? .current
    }
}
