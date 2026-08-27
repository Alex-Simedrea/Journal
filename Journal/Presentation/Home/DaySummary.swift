import Foundation

nonisolated enum DayMovementIconKind: Hashable, Sendable {
    case transit(String)
    case workout(String)
}

nonisolated struct DayMovementIcon: Hashable, Identifiable, Sendable {
    let id: TimelineOccurrenceID
    let kind: DayMovementIconKind
}

nonisolated struct DayMovementSummary: Equatable, Sendable {
    let icons: [DayMovementIcon]
    let distanceMeters: Double?
    let durationSeconds: TimeInterval?
    let needsReview: Bool
}

nonisolated struct DayFeaturedPlace: Equatable, Sendable {
    let occurrenceID: TimelineOccurrenceID
    let location: TimelineLocationSnapshot
    let durationSeconds: TimeInterval?
    let timeZoneIdentifier: String
    let needsReview: Bool
}

nonisolated struct DayWakeSummary: Equatable, Sendable {
    let wakeTime: Date
    let durationSeconds: TimeInterval?
    let timeZoneIdentifier: String
}

nonisolated struct DayWeatherRequest: Hashable, Sendable {
    let day: TimelineDayKey
    let startDate: Date
    let endDate: Date
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String

    var presentationDate: Date {
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        guard let interval = day.dateInterval(in: timeZone) else {
            return startDate.addingTimeInterval(
                endDate.timeIntervalSince(startDate) / 2
            )
        }
        return interval.start.addingTimeInterval(interval.duration / 2)
    }

    func isCompleted(at date: Date = .now) -> Bool {
        date >= endDate
    }
}

nonisolated struct DayWeatherSummary: Equatable, Sendable {
    let condition: String
    let symbolName: String
    let highTemperatureCelsius: Double
    let maximumHumidity: Double
    let date: Date

    var entryWeather: EntryWeather {
        EntryWeather(
            condition: condition,
            symbolName: symbolName,
            temperatureCelsius: highTemperatureCelsius,
            humidity: maximumHumidity,
            date: date
        )
    }
}

nonisolated extension PersistedDayWeather {
    init(request: DayWeatherRequest, summary: DayWeatherSummary) {
        year = request.day.year
        month = request.day.month
        day = request.day.day
        latitude = request.latitude
        longitude = request.longitude
        timeZoneIdentifier = request.timeZoneIdentifier
        weather = summary.entryWeather
        isFinal = request.isCompleted()
    }

    func matches(_ request: DayWeatherRequest) -> Bool {
        year == request.day.year
            && month == request.day.month
            && day == request.day.day
            && timeZoneIdentifier == request.timeZoneIdentifier
            && abs(latitude - request.latitude) < 0.000_01
            && abs(longitude - request.longitude) < 0.000_01
    }

    var summary: DayWeatherSummary {
        DayWeatherSummary(
            condition: weather.condition,
            symbolName: weather.symbolName,
            highTemperatureCelsius: weather.temperatureCelsius,
            maximumHumidity: weather.humidity,
            date: weather.date
        )
    }

    var needsRefresh: Bool {
        isFinal == false
    }
}

nonisolated struct DaySummary: Equatable, Identifiable, Sendable {
    let day: TimelineDayKey
    let occurrences: [TimelineOccurrence]
    let overviewData: TimelineOverviewData
    let showsOverviewMap: Bool
    let people: [TimelinePersonSnapshot]
    let peopleNeedReview: Bool
    let photos: [PhotoReference]
    let movement: DayMovementSummary?
    let wakeUp: DayWakeSummary?
    let featuredPlace: DayFeaturedPlace?
    let weatherRequest: DayWeatherRequest?
    let needsReview: Bool
    let showsNeedsReviewPlaceholder: Bool

    var id: TimelineDayKey { day }
}

enum DaySummaryDatePresentation {
    static func dayTitle(
        for day: TimelineDayKey,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let includesYear = day.year != calendar.component(.year, from: now)
        let dateTitle = "\(monthName(for: day, calendar: calendar)) \(day.day)"
        let datedTitle = includesYear
            ? "\(dateTitle), \(day.year)"
            : dateTitle
        return "\(weekdayName(for: day, calendar: calendar)), \(datedTitle)"
    }

    static func monthTitle(
        for day: TimelineDayKey,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let includesYear = day.year != calendar.component(.year, from: now)
        let month = monthName(for: day, calendar: calendar)
        return includesYear ? "\(month) \(day.year)" : month
    }

    private static func monthName(
        for day: TimelineDayKey,
        calendar: Calendar
    ) -> String {
        let symbols = calendar.monthSymbols
        guard symbols.indices.contains(day.month - 1) else { return "" }
        return symbols[day.month - 1]
    }

    private static func weekdayName(
        for day: TimelineDayKey,
        calendar: Calendar
    ) -> String {
        let date = day.displayDate(in: calendar.timeZone)
        let weekday = calendar.component(.weekday, from: date) - 1
        guard calendar.weekdaySymbols.indices.contains(weekday) else {
            return ""
        }
        return calendar.weekdaySymbols[weekday]
    }
}

nonisolated enum DaySummaryProjector {
    static func makeSummaries(
        entries: [TimelineEntrySnapshot]
    ) -> [DaySummary] {
        candidateDays(for: entries).compactMap { day in
            let projection = TimelineProjection.project(entries: entries, for: day)
            guard !projection.occurrences.isEmpty
                    || !projection.reviewOccurrences.isEmpty else {
                return nil
            }
            return makeSummary(day: day, projection: projection)
        }
    }

    static func candidateDays(
        for entries: [TimelineEntrySnapshot]
    ) -> [TimelineDayKey] {
        var result: Set<TimelineDayKey> = []

        for entry in entries {
            if entry.kind == .wakeUp {
                if let endTime = entry.endTime {
                    result.insert(
                        TimelineDayKey(
                            date: endTime,
                            timeZone: timeZone(
                                entry.endTimeZoneIdentifier,
                                fallback: entry.creationTimeZoneIdentifier
                            )
                        )
                    )
                } else {
                    result.insert(
                        TimelineDayKey(
                            date: entry.createdAt,
                            timeZone: timeZone(
                                entry.creationTimeZoneIdentifier,
                                fallback: TimeZone.current.identifier
                            )
                        )
                    )
                }
                continue
            }

            guard let startTime = entry.startTime,
                  let endTime = entry.endTime,
                  endTime > startTime else {
                result.insert(
                    TimelineDayKey(
                        date: entry.createdAt,
                        timeZone: timeZone(
                            entry.creationTimeZoneIdentifier,
                            fallback: TimeZone.current.identifier
                        )
                    )
                )
                continue
            }

            let startZone = timeZone(
                entry.startTimeZoneIdentifier,
                fallback: entry.creationTimeZoneIdentifier
            )
            var day = TimelineDayKey(date: startTime, timeZone: startZone)
            while let interval = day.dateInterval(in: startZone),
                  interval.start < endTime {
                if startTime < interval.end {
                    result.insert(day)
                }
                let next = day.addingDays(1)
                guard next != day else { break }
                day = next
            }

            let movesAcrossZones = entry.kind == .transit
                || entry.workoutMovementKind == .moving
            let endZone = timeZone(
                entry.endTimeZoneIdentifier,
                fallback: entry.creationTimeZoneIdentifier
            )
            if movesAcrossZones, startZone.identifier != endZone.identifier {
                result.insert(TimelineDayKey(date: endTime, timeZone: endZone))
            }
        }

        return result.sorted()
    }

    static func nearestDay(
        to target: TimelineDayKey,
        in days: [TimelineDayKey]
    ) -> TimelineDayKey? {
        days.min { lhs, rhs in
            let lhsDistance = dayDistance(lhs, target)
            let rhsDistance = dayDistance(rhs, target)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            let lhsIsNext = lhs >= target
            let rhsIsNext = rhs >= target
            if lhsIsNext != rhsIsNext {
                return lhsIsNext
            }
            return lhs < rhs
        }
    }

    private static func makeSummary(
        day: TimelineDayKey,
        projection: TimelineProjection
    ) -> DaySummary {
        let occurrences = (
            projection.occurrences + projection.reviewOccurrences
        ).sorted { $0.sortTime < $1.sortTime }
        let movementOccurrences = occurrences.filter {
            $0.kind == .transit
                || ($0.kind == .workout
                    && $0.snapshot.workoutMovementKind == .moving)
        }
        let featuredPlaces = featuredPlaces(in: occurrences)
        let weatherFeaturedPlace = featuredPlace(
            from: featuredPlaces,
            occurrences: occurrences
        )
        let featuredPlace = Set(featuredPlaces.map(\.location.id)).count > 1
            ? weatherFeaturedPlace
            : nil
        let weatherRequest = weatherRequest(
            for: day,
            featuredPlace: weatherFeaturedPlace,
            occurrences: occurrences
        )
        let mappedLocations = occurrences.flatMap { occurrence in
            mappedLocations(occurrence)
        }
            .filter(\.hasCoordinate)
        let distinctLocationIDs = Set(mappedLocations.map(\.id))
        let showsOverview = !movementOccurrences.isEmpty
            || distinctLocationIDs.count >= 2

        return DaySummary(
            day: day,
            occurrences: occurrences,
            overviewData: showsOverview
                ? TimelineOverviewData.make(
                    occurrences: projection.occurrences
                )
                : TimelineOverviewData(),
            showsOverviewMap: showsOverview,
            people: uniquePeople(in: occurrences),
            peopleNeedReview: occurrences.contains { occurrence in
                occurrence.snapshot.reviews.contains {
                    $0.target == .people
                }
            },
            photos: uniquePhotos(in: occurrences),
            movement: movementSummary(movementOccurrences),
            wakeUp: wakeSummary(in: occurrences),
            featuredPlace: featuredPlace,
            weatherRequest: weatherRequest,
            needsReview: occurrences.contains {
                $0.needsReview || !$0.snapshot.reviews.isEmpty
            },
            showsNeedsReviewPlaceholder: projection.occurrences.isEmpty
                && !projection.reviewOccurrences.isEmpty
        )
    }

    private static func movementSummary(
        _ occurrences: [TimelineOccurrence]
    ) -> DayMovementSummary? {
        guard !occurrences.isEmpty else { return nil }
        let distances = occurrences.compactMap { occurrence in
            occurrence.kind == .transit
                ? occurrence.snapshot.transitDistanceMeters
                : occurrence.snapshot.workoutDistanceMeters
        }
        let durations = occurrences.compactMap { occurrence -> TimeInterval? in
            guard let start = occurrence.startTime,
                  let end = occurrence.endTime,
                  end > start else { return nil }
            return end.timeIntervalSince(start)
        }
        var seenMovementTypes: Set<String> = []
        let icons = occurrences.compactMap { occurrence -> DayMovementIcon? in
            if occurrence.kind == .transit {
                let normalizedType = occurrence.transitType
                    .folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: .current
                    )
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard seenMovementTypes.insert(
                    "transit:\(normalizedType)"
                ).inserted else {
                    return nil
                }
                return DayMovementIcon(
                    id: occurrence.id,
                    kind: .transit(occurrence.transitType)
                )
            }
            let systemImageName = occurrence.snapshot.workoutSystemImageName
            guard seenMovementTypes.insert(
                "workout:\(systemImageName)"
            ).inserted else {
                return nil
            }
            return DayMovementIcon(
                id: occurrence.id,
                kind: .workout(systemImageName)
            )
        }
        return DayMovementSummary(
            icons: icons,
            distanceMeters: distances.isEmpty ? nil : distances.reduce(0, +),
            durationSeconds: durations.isEmpty ? nil : durations.reduce(0, +),
            needsReview: occurrences.contains {
                $0.needsReview || !$0.snapshot.reviews.isEmpty
            }
        )
    }

    private static func featuredPlaces(
        in occurrences: [TimelineOccurrence]
    ) -> [DayFeaturedPlace] {
        occurrences.compactMap { occurrence -> DayFeaturedPlace? in
            let location: TimelineLocationSnapshot?
            switch occurrence.kind {
            case .placeVisit:
                location = occurrence.snapshot.visitLocation
            case .workout where occurrence.snapshot.workoutMovementKind
                    == .staticWorkout:
                location = occurrence.snapshot.workoutPlaceLocation
            default:
                location = nil
            }
            guard let location else { return nil }
            let duration = duration(of: occurrence)
            return DayFeaturedPlace(
                occurrenceID: occurrence.id,
                location: location,
                durationSeconds: duration,
                timeZoneIdentifier: occurrence.timeZoneIdentifier,
                needsReview: occurrence.snapshot.reviews.contains {
                    $0.target == .place
                }
            )
        }
    }

    private static func featuredPlace(
        from candidates: [DayFeaturedPlace],
        occurrences: [TimelineOccurrence]
    ) -> DayFeaturedPlace? {
        candidates.max { lhs, rhs in
            let lhsDuration = lhs.durationSeconds ?? -1
            let rhsDuration = rhs.durationSeconds ?? -1
            if lhsDuration != rhsDuration {
                return lhsDuration < rhsDuration
            }
            return occurrenceSortTime(lhs.occurrenceID, in: occurrences)
                > occurrenceSortTime(rhs.occurrenceID, in: occurrences)
        }
    }

    private static func weatherRequest(
        for day: TimelineDayKey,
        featuredPlace: DayFeaturedPlace?,
        occurrences: [TimelineOccurrence]
    ) -> DayWeatherRequest? {
        let anchor: (TimelineLocationSnapshot, String)?
        if let featuredPlace, featuredPlace.location.hasCoordinate {
            anchor = (
                featuredPlace.location,
                featuredPlace.timeZoneIdentifier
            )
        } else {
            anchor = closestLocationToNoon(on: day, in: occurrences)
        }
        guard let (location, timeZoneIdentifier) = anchor else { return nil }
        let zone = timeZone(
            timeZoneIdentifier,
            fallback: TimeZone.current.identifier
        )
        guard let interval = day.dateInterval(in: zone) else { return nil }
        return DayWeatherRequest(
            day: day,
            startDate: interval.start,
            endDate: interval.end,
            latitude: location.latitude,
            longitude: location.longitude,
            timeZoneIdentifier: zone.identifier
        )
    }

    private static func closestLocationToNoon(
        on day: TimelineDayKey,
        in occurrences: [TimelineOccurrence]
    ) -> (TimelineLocationSnapshot, String)? {
        let candidates = occurrences.flatMap { occurrence in
            mappedLocations(occurrence).map {
                ($0, occurrence.timeZoneIdentifier, occurrence.sortTime)
            }
        }.filter { $0.0.hasCoordinate }
        guard !candidates.isEmpty else { return nil }
        return candidates.min { lhs, rhs in
            let lhsZone = timeZone(lhs.1, fallback: TimeZone.current.identifier)
            let rhsZone = timeZone(rhs.1, fallback: TimeZone.current.identifier)
            let lhsNoon = day.dateInterval(in: lhsZone)?.start
                .addingTimeInterval(12 * 60 * 60) ?? lhs.2
            let rhsNoon = day.dateInterval(in: rhsZone)?.start
                .addingTimeInterval(12 * 60 * 60) ?? rhs.2
            return abs(lhs.2.timeIntervalSince(lhsNoon))
                < abs(rhs.2.timeIntervalSince(rhsNoon))
        }.map { ($0.0, $0.1) }
    }

    private static func uniquePeople(
        in occurrences: [TimelineOccurrence]
    ) -> [TimelinePersonSnapshot] {
        var seen: Set<UUID> = []
        return occurrences.flatMap(\.snapshot.people).filter {
            seen.insert($0.id).inserted
        }
    }

    private static func uniquePhotos(
        in occurrences: [TimelineOccurrence]
    ) -> [PhotoReference] {
        var seen: Set<String> = []
        return occurrences.flatMap(\.snapshot.photoReferences).filter {
            seen.insert($0.id).inserted
        }
    }

    private static func wakeSummary(
        in occurrences: [TimelineOccurrence]
    ) -> DayWakeSummary? {
        guard let wake = occurrences.last(where: { $0.kind == .wakeUp }),
              let wakeTime = wake.endTime else { return nil }
        return DayWakeSummary(
            wakeTime: wakeTime,
            durationSeconds: wake.wakeUpSleepDurationSeconds,
            timeZoneIdentifier: wake.timeZoneIdentifier
        )
    }

    private static func mappedLocations(
        _ occurrence: TimelineOccurrence
    ) -> [TimelineLocationSnapshot] {
        switch occurrence.kind {
        case .transit:
            [occurrence.snapshot.originLocation,
             occurrence.snapshot.destinationLocation].compactMap { $0 }
        case .placeVisit:
            [occurrence.snapshot.visitLocation].compactMap { $0 }
        case .workout where occurrence.snapshot.workoutMovementKind == .moving:
            [occurrence.snapshot.workoutOriginLocation,
             occurrence.snapshot.workoutDestinationLocation].compactMap { $0 }
        case .workout:
            [occurrence.snapshot.workoutPlaceLocation].compactMap { $0 }
        case .wakeUp:
            []
        }
    }

    private static func duration(
        of occurrence: TimelineOccurrence
    ) -> TimeInterval? {
        guard let start = occurrence.startTime,
              let end = occurrence.endTime,
              end > start else { return nil }
        return end.timeIntervalSince(start)
    }

    private static func occurrenceSortTime(
        _ id: TimelineOccurrenceID,
        in occurrences: [TimelineOccurrence]
    ) -> Date {
        occurrences.first { $0.id == id }?.sortTime ?? .distantFuture
    }

    private static func timeZone(
        _ identifier: String,
        fallback: String
    ) -> TimeZone {
        TimeZone(identifier: identifier)
            ?? TimeZone(identifier: fallback)
            ?? .current
    }

    private static func dayDistance(
        _ lhs: TimelineDayKey,
        _ rhs: TimelineDayKey
    ) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let lhsDate = lhs.displayDate(in: .gmt)
        let rhsDate = rhs.displayDate(in: .gmt)
        return abs(
            calendar.dateComponents([.day], from: lhsDate, to: rhsDate).day
                ?? .max
        )
    }
}
