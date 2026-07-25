import CoreLocation
import Foundation

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
    var wakeUpSleepDurationSeconds: Double? {
        snapshot.wakeUpSleepDurationSeconds
    }
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
    let transitPresentation: TimelineTransitRowPresentation?
    let endBoundaryNeedsReview: Bool
    let startBoundaryRenderedByPrevious: Bool

    var id: TimelineOccurrenceID { occurrence.id }
}

enum TimelineTransitBoundarySide: String, Hashable, Sendable {
    case origin
    case destination
}

struct TimelineTransitBoundaryID: Hashable, Sendable {
    let occurrenceID: TimelineOccurrenceID
    let side: TimelineTransitBoundarySide
}

struct TimelineTransitBoundaryPresentation: Hashable, Identifiable, Sendable {
    let occurrenceID: TimelineOccurrenceID
    let side: TimelineTransitBoundarySide
    let name: String
    let location: TimelineLocationSnapshot?
    let showsPseudoEntry: Bool
    let needsReview: Bool
    let followingTransitStart: TimelineTransitSharedStartPresentation?

    var id: TimelineTransitBoundaryID {
        TimelineTransitBoundaryID(
            occurrenceID: occurrenceID,
            side: side
        )
    }

    var systemImage: PlaceSystemImage {
        location?.systemImage ?? .mappin
    }
}

struct TimelineTransitSharedStartPresentation: Hashable, Sendable {
    let date: Date
    let timeZoneIdentifier: String
    let needsReview: Bool
}

struct TimelineTransitRowPresentation: Hashable, Sendable {
    let origin: TimelineTransitBoundaryPresentation
    let destination: TimelineTransitBoundaryPresentation
    let showsReviewBadge: Bool
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
            if entry.kind == .wakeUp {
                if let wakeUp = wakeUpOccurrence(for: entry, on: day) {
                    occurrences.append(wakeUp)
                }
                continue
            }

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
        let relationships = occurrences.map { occurrence in
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
            return relationship
        }

        let rows = occurrences.enumerated().map { index, occurrence in
            let nextIndex = index + 1
            let previousOccurrence = index > occurrences.startIndex
                ? occurrences[index - 1]
                : nil
            let nextOccurrence = nextIndex < occurrences.endIndex
                ? occurrences[nextIndex]
                : nil
            let nextSharesBoundary = nextIndex < occurrences.endIndex
                && relationships[nextIndex] == .contiguous
            let sharesOriginWithPreviousTransit: Bool
            if let previousOccurrence {
                sharesOriginWithPreviousTransit =
                    transitBoundaryLocationsMatch(
                        previousOccurrence,
                        occurrence
                    )
            } else {
                sharesOriginWithPreviousTransit = false
            }
            let sharesDestinationWithNextTransit: Bool
            if let nextOccurrence {
                sharesDestinationWithNextTransit =
                    transitBoundaryLocationsMatch(
                        occurrence,
                        nextOccurrence
                    )
            } else {
                sharesDestinationWithNextTransit = false
            }
            return TimelineRow(
                occurrence: occurrence,
                relationshipToPrevious: relationships[index],
                transitPresentation: transitPresentation(
                    for: occurrence,
                    previous: previousOccurrence,
                    next: nextOccurrence,
                    sharesOriginWithPreviousTransit:
                        sharesOriginWithPreviousTransit,
                    sharesDestinationWithNextTransit:
                        sharesDestinationWithNextTransit
                ),
                endBoundaryNeedsReview: occurrence.reviewsTime
                    || (nextSharesBoundary
                        && occurrences[nextIndex].reviewsTime),
                startBoundaryRenderedByPrevious:
                    sharesOriginWithPreviousTransit
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
        TimelineBoundaryMatcher.timesMatch(previousEnd, nextStart)
    }

    private static func transitPresentation(
        for occurrence: TimelineOccurrence,
        previous: TimelineOccurrence?,
        next: TimelineOccurrence?,
        sharesOriginWithPreviousTransit: Bool,
        sharesDestinationWithNextTransit: Bool
    ) -> TimelineTransitRowPresentation? {
        guard occurrence.kind == .transit else { return nil }

        let originNeedsReview = occurrence.snapshot.reviews.contains {
            $0.target == .origin
        }
        let ownDestinationNeedsReview = occurrence.snapshot.reviews.contains {
            $0.target == .destination
        }
        let followingOriginNeedsReview: Bool
        if sharesDestinationWithNextTransit, let next {
            followingOriginNeedsReview = next.snapshot.reviews.contains {
                $0.target == .origin
            }
        } else {
            followingOriginNeedsReview = false
        }
        let destinationNeedsReview = ownDestinationNeedsReview
            || followingOriginNeedsReview
        let originMatches = TimelineBoundaryMatcher.matches(
            transitTime: occurrence.visibleStartTime,
            transitLocation: occurrence.snapshot.originLocation,
            adjacentTime: previous?.visibleEndTime,
            adjacentLocation: previous.flatMap(boundaryEndLocation)
        )
        let destinationMatches = TimelineBoundaryMatcher.matches(
            transitTime: occurrence.visibleEndTime,
            transitLocation: occurrence.snapshot.destinationLocation,
            adjacentTime: next?.visibleStartTime,
            adjacentLocation: next.flatMap(boundaryStartLocation)
        )
        let followingTransitStart =
            sharesDestinationWithNextTransit
            ? sharedStartPresentation(
                before: next
            )
            : nil

        let origin = TimelineTransitBoundaryPresentation(
            occurrenceID: occurrence.id,
            side: .origin,
            name: occurrence.origin,
            location: occurrence.snapshot.originLocation,
            showsPseudoEntry: !originMatches
                && !sharesOriginWithPreviousTransit,
            needsReview: originNeedsReview,
            followingTransitStart: nil
        )
        let destination = TimelineTransitBoundaryPresentation(
            occurrenceID: occurrence.id,
            side: .destination,
            name: occurrence.destination,
            location: occurrence.snapshot.destinationLocation,
            showsPseudoEntry: sharesDestinationWithNextTransit
                || !destinationMatches,
            needsReview: destinationNeedsReview,
            followingTransitStart: followingTransitStart
        )
        let centrallyRenderedTargets: Set<TimelineReviewTarget> = [
            .entryKind,
            .transitType,
            .people,
        ]
        let hasCentralReview = occurrence.snapshot.reviews.contains { review in
            centrallyRenderedTargets.contains(review.target)
                || (review.target == .origin
                    && !origin.showsPseudoEntry
                    && !sharesOriginWithPreviousTransit)
                || (review.target == .destination
                    && !destination.showsPseudoEntry)
        }
        let hasUnclassifiedReview = occurrence.needsReview
            && occurrence.snapshot.reviews.isEmpty

        return TimelineTransitRowPresentation(
            origin: origin,
            destination: destination,
            showsReviewBadge: hasCentralReview || hasUnclassifiedReview
        )
    }

    private static func sharedStartPresentation(
        before next: TimelineOccurrence?
    ) -> TimelineTransitSharedStartPresentation? {
        guard let next,
              let nextStart = next.visibleStartTime else {
            return nil
        }
        return TimelineTransitSharedStartPresentation(
            date: nextStart,
            timeZoneIdentifier: next.timeZoneIdentifier,
            needsReview: next.reviewsTime
        )
    }

    private static func transitBoundaryLocationsMatch(
        _ previous: TimelineOccurrence,
        _ next: TimelineOccurrence
    ) -> Bool {
        guard previous.kind == .transit,
              next.kind == .transit,
              let visibleEnd = previous.visibleEndTime,
              visibleEnd == previous.endTime,
              let visibleStart = next.visibleStartTime,
              visibleStart == next.startTime,
              let destination = previous.snapshot.destinationLocation,
              let origin = next.snapshot.originLocation else {
            return false
        }
        return TimelineBoundaryMatcher.locationsMatch(destination, origin)
    }

    nonisolated private static func boundaryStartLocation(
        _ occurrence: TimelineOccurrence
    ) -> TimelineLocationSnapshot? {
        switch occurrence.kind {
        case .transit:
            occurrence.snapshot.originLocation
        case .placeVisit:
            occurrence.snapshot.visitLocation
        case .workout:
            occurrence.snapshot.workoutMovementKind == .moving
                ? occurrence.snapshot.workoutOriginLocation
                : occurrence.snapshot.workoutPlaceLocation
        case .wakeUp:
            nil
        }
    }

    nonisolated private static func boundaryEndLocation(
        _ occurrence: TimelineOccurrence
    ) -> TimelineLocationSnapshot? {
        switch occurrence.kind {
        case .transit:
            occurrence.snapshot.destinationLocation
        case .placeVisit:
            occurrence.snapshot.visitLocation
        case .workout:
            occurrence.snapshot.workoutMovementKind == .moving
                ? occurrence.snapshot.workoutDestinationLocation
                : occurrence.snapshot.workoutPlaceLocation
        case .wakeUp:
            nil
        }
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

    private static func wakeUpOccurrence(
        for entry: TimelineEntrySnapshot,
        on day: TimelineDayKey
    ) -> TimelineOccurrence? {
        guard let wakeTime = entry.endTime else { return nil }
        let wakeTimeZone = timeZone(
            identifier: entry.endTimeZoneIdentifier,
            fallbackIdentifier: entry.creationTimeZoneIdentifier
        )
        guard TimelineDayKey(date: wakeTime, timeZone: wakeTimeZone) == day else {
            return nil
        }
        return occurrence(
            entry: entry,
            day: day,
            role: .wakeUp,
            timeZoneIdentifier: wakeTimeZone.identifier,
            endTimeZoneIdentifier: wakeTimeZone.identifier,
            sortTime: wakeTime,
            visibleStartTime: wakeTime,
            visibleEndTime: wakeTime
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

enum TimelineBoundaryMatcher {
    static let maximumSemanticDistanceMeters: CLLocationDistance = 50

    static func matches(
        transitTime: Date?,
        transitLocation: TimelineLocationSnapshot?,
        adjacentTime: Date?,
        adjacentLocation: TimelineLocationSnapshot?
    ) -> Bool {
        guard let transitTime,
              let adjacentTime,
              timesMatch(transitTime, adjacentTime),
              let transitLocation,
              let adjacentLocation else {
            return false
        }
        return locationsMatch(transitLocation, adjacentLocation)
    }

    static func timesMatch(_ lhs: Date, _ rhs: Date) -> Bool {
        floor(lhs.timeIntervalSinceReferenceDate / 60)
            == floor(rhs.timeIntervalSinceReferenceDate / 60)
    }

    static func locationsMatch(
        _ lhs: TimelineLocationSnapshot,
        _ rhs: TimelineLocationSnapshot
    ) -> Bool {
        if let lhsPlaceID = lhs.savedPlaceID,
           let rhsPlaceID = rhs.savedPlaceID {
            return lhsPlaceID == rhsPlaceID
        }

        if lhs.savedPlaceID == nil,
           rhs.savedPlaceID == nil,
           lhs == rhs {
            return true
        }

        guard normalizedLocationName(lhs.name)
            == normalizedLocationName(rhs.name) else {
            return false
        }

        guard lhs.hasCoordinate, rhs.hasCoordinate else {
            return true
        }

        return CLLocation(
            latitude: lhs.latitude,
            longitude: lhs.longitude
        ).distance(
            from: CLLocation(
                latitude: rhs.latitude,
                longitude: rhs.longitude
            )
        ) <= maximumSemanticDistanceMeters
    }

    private static func normalizedLocationName(
        _ value: String
    ) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .components(
                separatedBy: CharacterSet.alphanumerics.inverted
            )
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
