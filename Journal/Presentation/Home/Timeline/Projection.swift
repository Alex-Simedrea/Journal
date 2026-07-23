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
