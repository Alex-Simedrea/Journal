//
//  TimelineProjection.swift
//  Journal
//

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
        let startComponents = DateComponents(
            year: year,
            month: month,
            day: day
        )
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
    let origin: String
    let destination: String
    let visitPlace: String
    let visitSystemImage: PlaceSystemImage
    let workoutActivityName: String
    let workoutSystemImageName: String
    let workoutMovementKind: WorkoutMovementKind?
    let workoutDistanceMeters: Double?
    let workoutActiveEnergyKilocalories: Double?
    let workoutOrigin: String
    let workoutDestination: String
    let workoutPlace: String

    init(entry: LogEntry) {
        let details = entry.transitDetails
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
        transitType = details?.type ?? "Transit"
        origin = details?.originPlace?.name
            ?? details?.originRawText
            ?? "Unknown origin"
        destination = details?.destinationPlace?.name
            ?? details?.destinationRawText
            ?? "Unknown destination"
        visitPlace = entry.placeVisitDetails?.place?.name
            ?? entry.placeVisitDetails?.placeRawText
            ?? "Unknown place"
        visitSystemImage = entry.placeVisitDetails?.place?.systemImage
            ?? .mappin
        let workout = entry.workoutDetails
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
        workoutPlace: String = "Place"
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
        self.origin = origin
        self.destination = destination
        self.visitPlace = visitPlace
        self.visitSystemImage = visitSystemImage
        self.workoutActivityName = workoutActivityName
        self.workoutSystemImageName = workoutSystemImageName
        self.workoutMovementKind = workoutMovementKind
        self.workoutDistanceMeters = workoutDistanceMeters
        self.workoutActiveEnergyKilocalories =
            workoutActiveEnergyKilocalories
        self.workoutOrigin = workoutOrigin
        self.workoutDestination = workoutDestination
        self.workoutPlace = workoutPlace
    }
}

struct TimelineOccurrence: Hashable, Identifiable, Sendable {
    let id: TimelineOccurrenceID
    let entryID: UUID
    let role: TimelineOccurrenceRole
    let timeZoneIdentifier: String
    let sortTime: Date
    let visibleStartTime: Date?
    let visibleEndTime: Date?
    let startTime: Date?
    let endTime: Date?
    let needsReview: Bool
    let kind: LogKind
    let transitType: String
    let origin: String
    let destination: String
    let visitPlace: String
    let visitSystemImage: PlaceSystemImage
    let workoutActivityName: String
    let workoutSystemImageName: String
    let workoutMovementKind: WorkoutMovementKind?
    let workoutDistanceMeters: Double?
    let workoutActiveEnergyKilocalories: Double?
    let workoutOrigin: String
    let workoutDestination: String
    let workoutPlace: String
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
            if let dayInterval = day.dateInterval(in: startZone),
               startTime < dayInterval.end,
               endTime > dayInterval.start {
                occurrences.append(
                    occurrence(
                        entry: entry,
                        day: day,
                        role: .intervalDay,
                        timeZoneIdentifier: startZone.identifier,
                        sortTime: max(startTime, dayInterval.start),
                        visibleStartTime: max(startTime, dayInterval.start),
                        visibleEndTime: min(endTime, dayInterval.end)
                    )
                )
            }

            let endZone = timeZone(
                identifier: entry.endTimeZoneIdentifier,
                fallbackIdentifier: entry.creationTimeZoneIdentifier
            )
            if (entry.kind == .transit
                || entry.workoutMovementKind == .moving),
               startZone.identifier != endZone.identifier,
               TimelineDayKey(date: endTime, timeZone: endZone) == day {
                occurrences.append(
                    occurrence(
                        entry: entry,
                        day: day,
                        role: .crossZoneArrival,
                        timeZoneIdentifier: endZone.identifier,
                        sortTime: endTime,
                        visibleStartTime: nil,
                        visibleEndTime: endTime
                    )
                )
            }
        }

        occurrences.sort(by: occurrenceOrder)
        reviews.sort(by: occurrenceOrder)

        var listItems: [TimelineListItem] = []
        var previous: TimelineOccurrence?
        for occurrence in occurrences {
            if let previous,
               previous.timeZoneIdentifier != occurrence.timeZoneIdentifier {
                listItems.append(
                    .timeZoneChange(
                        TimelineTimeZoneChange(
                            id: occurrence.id,
                            fromTimeZoneIdentifier: previous.timeZoneIdentifier,
                            toTimeZoneIdentifier: occurrence.timeZoneIdentifier,
                            date: occurrence.sortTime
                        )
                    )
                )
            }
            listItems.append(.occurrence(occurrence))
            previous = occurrence
        }

        return TimelineProjection(
            occurrences: occurrences,
            reviewOccurrences: reviews,
            listItems: listItems
        )
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
            sortTime: sortTime,
            visibleStartTime: visibleStartTime,
            visibleEndTime: visibleEndTime,
            startTime: entry.startTime,
            endTime: entry.endTime,
            needsReview: entry.needsReview,
            kind: entry.kind,
            transitType: entry.transitType,
            origin: entry.origin,
            destination: entry.destination,
            visitPlace: entry.visitPlace,
            visitSystemImage: entry.visitSystemImage,
            workoutActivityName: entry.workoutActivityName,
            workoutSystemImageName: entry.workoutSystemImageName,
            workoutMovementKind: entry.workoutMovementKind,
            workoutDistanceMeters: entry.workoutDistanceMeters,
            workoutActiveEnergyKilocalories:
                entry.workoutActiveEnergyKilocalories,
            workoutOrigin: entry.workoutOrigin,
            workoutDestination: entry.workoutDestination,
            workoutPlace: entry.workoutPlace
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
