import Foundation

nonisolated enum JournalSummaryScale: String, CaseIterable, Identifiable, Sendable {
    case years = "Years"
    case months = "Months"
    case days = "Days"

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .years: "Years"
        case .months: "Months"
        case .days: "Days"
        }
    }
}

nonisolated struct MonthKey: Comparable, Hashable, Identifiable, Sendable {
    let year: Int
    let month: Int

    var id: String { "\(year)-\(month)" }

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(day: TimelineDayKey) {
        self.init(year: day.year, month: day.month)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

nonisolated struct YearKey: Comparable, Hashable, Identifiable, Sendable {
    let year: Int
    var id: Int { year }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.year < rhs.year }
}

nonisolated enum PeriodSummaryKey: Hashable, Identifiable, Sendable {
    case month(MonthKey)
    case year(YearKey)

    var id: String {
        switch self {
        case .month(let key): "month-\(key.id)"
        case .year(let key): "year-\(key.id)"
        }
    }
}

nonisolated struct PeriodPersonSummary: Equatable, Identifiable, Sendable {
    let person: TimelinePersonSnapshot
    let loggedDuration: TimeInterval
    let dayCount: Int
    let entryCount: Int

    var id: UUID { person.id }
}

nonisolated struct PeriodPlaceSummary: Equatable, Identifiable, Sendable {
    let location: TimelineLocationSnapshot
    let duration: TimeInterval
    let visitCount: Int

    var id: String { location.id }
}

nonisolated struct PeriodRouteSummary: Equatable, Sendable {
    let count: Int
    let originName: String
    let destinationName: String
    let mapData: TimelineOverviewData
    let representativeEntryID: UUID?
    let workoutUUID: UUID?

    init(
        count: Int,
        originName: String,
        destinationName: String,
        mapData: TimelineOverviewData,
        representativeEntryID: UUID? = nil,
        workoutUUID: UUID? = nil
    ) {
        self.count = count
        self.originName = originName
        self.destinationName = destinationName
        self.mapData = mapData
        self.representativeEntryID = representativeEntryID
        self.workoutUUID = workoutUUID
    }
}

nonisolated struct PeriodGeographySummary: Equatable, Identifiable, Sendable {
    let name: String
    let code: String?
    let visitCount: Int

    var id: String { code ?? name }
}

nonisolated struct PeriodSleepSummary: Equatable, Sendable {
    let sampleCount: Int
    let averageWakeMinute: Int
    let averageDuration: TimeInterval?
    let consistencyMinutes: Int
}

nonisolated struct PeriodJourneySummary: Equatable, Sendable {
    let day: TimelineDayKey
    let distanceMeters: Double
    let originName: String
    let destinationName: String
    let mapData: TimelineOverviewData
    let representativeEntryID: UUID?
    let workoutUUID: UUID?

    init(
        day: TimelineDayKey,
        distanceMeters: Double,
        originName: String,
        destinationName: String,
        mapData: TimelineOverviewData = TimelineOverviewData(),
        representativeEntryID: UUID? = nil,
        workoutUUID: UUID? = nil
    ) {
        self.day = day
        self.distanceMeters = distanceMeters
        self.originName = originName
        self.destinationName = destinationName
        self.mapData = mapData
        self.representativeEntryID = representativeEntryID
        self.workoutUUID = workoutUUID
    }
}

nonisolated struct PeriodSummary: Equatable, Identifiable, Sendable {
    let key: PeriodSummaryKey
    let days: [DaySummary]
    let entryCount: Int
    let overviewData: TimelineOverviewData
    let people: [PeriodPersonSummary]
    let movement: DayMovementSummary?
    let frequentRoute: PeriodRouteSummary?
    let mostVisitedPlace: PeriodPlaceSummary?
    let cities: [PeriodGeographySummary]
    let countries: [PeriodGeographySummary]
    let photos: [PhotoReference]
    let totalPhotoCount: Int
    let busiestDay: TimelineDayKey?
    let busiestMonth: MonthKey?
    let longestJourney: PeriodJourneySummary?
    let sleep: PeriodSleepSummary?
    let activity: [Int]
    let reviewCount: Int
    let newGroundCount: Int

    var id: PeriodSummaryKey { key }
    var firstDay: TimelineDayKey? { days.first?.day }

    var monthKey: MonthKey? {
        guard case .month(let key) = key else { return nil }
        return key
    }

    var yearKey: YearKey? {
        guard case .year(let key) = key else { return nil }
        return key
    }
}

enum PeriodSummaryDatePresentation {
    static func title(for key: MonthKey, calendar: Calendar = .current) -> String {
        guard calendar.monthSymbols.indices.contains(key.month - 1) else {
            return String(key.year)
        }
        return "\(calendar.monthSymbols[key.month - 1]) \(key.year)"
    }

    static func title(for key: YearKey) -> String { String(key.year) }
}

nonisolated enum PeriodSummaryProjector {
    private struct AttributedEntry {
        let snapshot: TimelineEntrySnapshot
        let day: TimelineDayKey
        let occurrence: TimelineOccurrence?
    }

    static func makeMonthSummaries(
        entries: [TimelineEntrySnapshot],
        daySummaries: [DaySummary],
        photoMetadata: [String: PeriodPhotoMetadata] = [:]
    ) -> [PeriodSummary] {
        let attributed = attributedEntries(entries, daySummaries: daySummaries)
        return Dictionary(grouping: attributed) { MonthKey(day: $0.day) }
            .map { key, entries in
                makeSummary(
                    key: .month(key),
                    entries: entries,
                    days: daySummaries.filter { MonthKey(day: $0.day) == key },
                    allEntries: attributed,
                    photoMetadata: photoMetadata
                )
            }
            .sorted { $0.monthKey! < $1.monthKey! }
    }

    static func makeYearSummaries(
        entries: [TimelineEntrySnapshot],
        daySummaries: [DaySummary],
        photoMetadata: [String: PeriodPhotoMetadata] = [:]
    ) -> [PeriodSummary] {
        let attributed = attributedEntries(entries, daySummaries: daySummaries)
        return Dictionary(grouping: attributed) { YearKey(year: $0.day.year) }
            .map { key, entries in
                makeSummary(
                    key: .year(key),
                    entries: entries,
                    days: daySummaries.filter { $0.day.year == key.year },
                    allEntries: attributed,
                    photoMetadata: photoMetadata
                )
            }
            .sorted { $0.yearKey! < $1.yearKey! }
    }

    static func primaryDay(for entry: TimelineEntrySnapshot) -> TimelineDayKey {
        if entry.kind == .wakeUp, let wakeTime = entry.endTime {
            return TimelineDayKey(
                date: wakeTime,
                timeZone: zone(
                    entry.endTimeZoneIdentifier,
                    fallback: entry.creationTimeZoneIdentifier
                )
            )
        }
        if let start = entry.startTime {
            return TimelineDayKey(
                date: start,
                timeZone: zone(
                    entry.startTimeZoneIdentifier,
                    fallback: entry.creationTimeZoneIdentifier
                )
            )
        }
        return TimelineDayKey(
            date: entry.createdAt,
            timeZone: zone(
                entry.creationTimeZoneIdentifier,
                fallback: TimeZone.current.identifier
            )
        )
    }

    private static func attributedEntries(
        _ entries: [TimelineEntrySnapshot],
        daySummaries: [DaySummary]
    ) -> [AttributedEntry] {
        let occurrences = daySummaries.flatMap(\.occurrences)
        return entries.map { entry in
            let day = primaryDay(for: entry)
            let occurrence = occurrences.first {
                $0.entryID == entry.id && $0.id.day == day
            } ?? occurrences.first { $0.entryID == entry.id }
            return AttributedEntry(
                snapshot: entry,
                day: day,
                occurrence: occurrence
            )
        }.sorted {
            if $0.day != $1.day { return $0.day < $1.day }
            let lhsDate = $0.snapshot.startTime ?? $0.snapshot.createdAt
            let rhsDate = $1.snapshot.startTime ?? $1.snapshot.createdAt
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return $0.snapshot.id.uuidString < $1.snapshot.id.uuidString
        }
    }

    private static func makeSummary(
        key: PeriodSummaryKey,
        entries: [AttributedEntry],
        days: [DaySummary],
        allEntries: [AttributedEntry],
        photoMetadata: [String: PeriodPhotoMetadata]
    ) -> PeriodSummary {
        let sortedDays = days.sorted { $0.day < $1.day }
        let people = peopleSummary(entries)
        let movement = movementSummary(entries)
        let route = frequentRoute(entries)
        let place = mostVisitedPlace(entries)
        let photos = representativePhotos(
            entries.flatMap(\.snapshot.photoReferences),
            metadata: photoMetadata
        )
        let citySummary = geographySummary(entries, city: true)
        let countrySummary = geographySummary(entries, city: false)
        let groupedByDay = Dictionary(grouping: entries, by: \.day)
        let busiestDay = groupedByDay.max { lhs, rhs in
            if lhs.value.count != rhs.value.count {
                return lhs.value.count < rhs.value.count
            }
            let lhsDuration = lhs.value.reduce(0) { $0 + duration($1.snapshot) }
            let rhsDuration = rhs.value.reduce(0) { $0 + duration($1.snapshot) }
            if lhsDuration != rhsDuration { return lhsDuration < rhsDuration }
            return lhs.key < rhs.key
        }?.key
        let groupedByMonth = Dictionary(grouping: entries) {
            MonthKey(day: $0.day)
        }
        let busiestMonth = groupedByMonth.max { lhs, rhs in
            if lhs.value.count != rhs.value.count {
                return lhs.value.count < rhs.value.count
            }
            let lhsDuration = lhs.value.reduce(0) { $0 + duration($1.snapshot) }
            let rhsDuration = rhs.value.reduce(0) { $0 + duration($1.snapshot) }
            if lhsDuration != rhsDuration { return lhsDuration < rhsDuration }
            return lhs.key < rhs.key
        }?.key
        let occurrences = entries.compactMap(\.occurrence).filter {
            $0.role != .unresolvedReview
        }

        return PeriodSummary(
            key: key,
            days: sortedDays,
            entryCount: entries.count,
            overviewData: TimelineOverviewData.makePeriod(
                occurrences: occurrences
            ),
            people: people,
            movement: movement,
            frequentRoute: route,
            mostVisitedPlace: place,
            cities: citySummary,
            countries: countrySummary,
            photos: photos,
            totalPhotoCount: Set(
                entries.flatMap(\.snapshot.photoReferences).map(\.id)
            ).count,
            busiestDay: busiestDay,
            busiestMonth: key.yearValue == nil ? nil : busiestMonth,
            longestJourney: longestJourney(entries),
            sleep: sleepSummary(entries),
            activity: activity(for: key, entries: entries),
            reviewCount: entries.filter {
                $0.snapshot.needsReview || !$0.snapshot.reviews.isEmpty
            }.count,
            newGroundCount: newGroundCount(
                key: key,
                entries: entries,
                allEntries: allEntries
            )
        )
    }

    private static func peopleSummary(
        _ entries: [AttributedEntry]
    ) -> [PeriodPersonSummary] {
        var people: [UUID: TimelinePersonSnapshot] = [:]
        var intervals: [UUID: [DateInterval]] = [:]
        var days: [UUID: Set<TimelineDayKey>] = [:]
        var counts: [UUID: Int] = [:]
        for entry in entries {
            for person in entry.snapshot.people {
                people[person.id] = person
                days[person.id, default: []].insert(entry.day)
                counts[person.id, default: 0] += 1
                if let interval = interval(entry.snapshot) {
                    intervals[person.id, default: []].append(interval)
                }
            }
        }
        return people.values.map { person in
            PeriodPersonSummary(
                person: person,
                loggedDuration: unionDuration(intervals[person.id, default: []]),
                dayCount: days[person.id]?.count ?? 0,
                entryCount: counts[person.id] ?? 0
            )
        }
        .sorted {
            if $0.loggedDuration != $1.loggedDuration {
                return $0.loggedDuration > $1.loggedDuration
            }
            if $0.dayCount != $1.dayCount { return $0.dayCount > $1.dayCount }
            if $0.entryCount != $1.entryCount {
                return $0.entryCount > $1.entryCount
            }
            let nameOrder = $0.person.name.localizedStandardCompare($1.person.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return $0.person.id.uuidString < $1.person.id.uuidString
        }
    }

    private static func movementSummary(
        _ entries: [AttributedEntry]
    ) -> DayMovementSummary? {
        let moving = entries.filter {
            $0.snapshot.kind == .transit
                || ($0.snapshot.kind == .workout
                    && $0.snapshot.workoutMovementKind == .moving)
        }
        guard !moving.isEmpty else { return nil }
        var typeCounts: [String: (Int, DayMovementIconKind, TimelineOccurrenceID)] = [:]
        for entry in moving {
            let kind: DayMovementIconKind
            let key: String
            if entry.snapshot.kind == .transit {
                kind = .transit(entry.snapshot.transitType)
                key = "transit-\(normalized(entry.snapshot.transitType))"
            } else {
                kind = .workout(entry.snapshot.workoutSystemImageName)
                key = "workout-\(entry.snapshot.workoutSystemImageName)"
            }
            let fallbackID = TimelineOccurrenceID(
                entryID: entry.snapshot.id,
                day: entry.day,
                timeZoneIdentifier: entry.snapshot.startTimeZoneIdentifier,
                role: .intervalDay
            )
            let current = typeCounts[key]
            typeCounts[key] = ((current?.0 ?? 0) + 1, kind, current?.2 ?? fallbackID)
        }
        let icons = typeCounts.sorted {
            if $0.value.0 != $1.value.0 { return $0.value.0 > $1.value.0 }
            return $0.key < $1.key
        }.map {
            DayMovementIcon(id: $0.value.2, kind: $0.value.1)
        }
        let distances = moving.compactMap { entry in
            entry.snapshot.kind == .transit
                ? entry.snapshot.transitDistanceMeters
                : entry.snapshot.workoutDistanceMeters
        }
        return DayMovementSummary(
            icons: icons,
            distanceMeters: distances.isEmpty ? nil : distances.reduce(0, +),
            durationSeconds: moving.map { duration($0.snapshot) }.reduce(0, +),
            needsReview: moving.contains { $0.snapshot.needsReview }
        )
    }

    private static func frequentRoute(
        _ entries: [AttributedEntry]
    ) -> PeriodRouteSummary? {
        let routed = entries.compactMap { entry -> (String, String, TimelineOccurrence)? in
            let snapshot = entry.snapshot
            let origin: TimelineLocationSnapshot?
            let destination: TimelineLocationSnapshot?
            if snapshot.kind == .transit {
                origin = snapshot.originLocation
                destination = snapshot.destinationLocation
            } else if snapshot.kind == .workout,
                      snapshot.workoutMovementKind == .moving {
                origin = snapshot.workoutOriginLocation
                destination = snapshot.workoutDestinationLocation
            } else {
                return nil
            }
            guard let origin, let destination,
                  origin.hasCoordinate, destination.hasCoordinate,
                  let occurrence = entry.occurrence else { return nil }
            return (locationIdentity(origin), locationIdentity(destination), occurrence)
        }
        let grouped = Dictionary(grouping: routed) { route in
            [route.0, route.1].sorted().joined(separator: "→")
        }
        guard let winningRoute = grouped.filter({ $0.value.count > 1 }).sorted(by: {
            if $0.value.count != $1.value.count {
                return $0.value.count > $1.value.count
            }
            return $0.key < $1.key
        }).first else { return nil }
        let winner = winningRoute.value
        guard let sample = winner.min(by: {
            $0.2.entryID.uuidString < $1.2.entryID.uuidString
        }) else { return nil }
        let occurrence = sample.2
        let snapshot = occurrence.snapshot
        let originName = snapshot.kind == .transit
            ? snapshot.origin : snapshot.workoutOrigin
        let destinationName = snapshot.kind == .transit
            ? snapshot.destination : snapshot.workoutDestination
        return PeriodRouteSummary(
            count: winner.count,
            originName: originName,
            destinationName: destinationName,
            mapData: TimelineOverviewData.make(occurrences: [occurrence]),
            representativeEntryID: occurrence.entryID,
            workoutUUID: snapshot.kind == .workout
                ? snapshot.workoutUUID : nil
        )
    }

    private static func mostVisitedPlace(
        _ entries: [AttributedEntry]
    ) -> PeriodPlaceSummary? {
        let places = entries.compactMap { entry -> (TimelineLocationSnapshot, Double)? in
            switch entry.snapshot.kind {
            case .placeVisit:
                entry.snapshot.visitLocation.map { ($0, duration(entry.snapshot)) }
            case .workout where entry.snapshot.workoutMovementKind == .staticWorkout:
                entry.snapshot.workoutPlaceLocation.map { ($0, duration(entry.snapshot)) }
            default: nil
            }
        }
        return Dictionary(grouping: places, by: { locationIdentity($0.0) })
            .values
            .map { values in
                PeriodPlaceSummary(
                    location: values[0].0,
                    duration: values.reduce(0) { $0 + $1.1 },
                    visitCount: values.count
                )
            }
            .sorted {
                if $0.duration != $1.duration { return $0.duration > $1.duration }
                if $0.visitCount != $1.visitCount {
                    return $0.visitCount > $1.visitCount
                }
                return $0.id < $1.id
            }.first
    }

    private static func geographySummary(
        _ entries: [AttributedEntry],
        city: Bool
    ) -> [PeriodGeographySummary] {
        var values: [String: (name: String, code: String?, count: Int)] = [:]
        for entry in entries {
            for location in geographicLocations(entry.snapshot) {
                let name = city ? location.cityName : location.countryName
                let code = city ? nil : location.countryCode
                guard let name, !name.isEmpty else { continue }
                let key = normalized(code ?? name)
                let current = values[key]
                values[key] = (name, code, (current?.count ?? 0) + 1)
            }
        }
        return values.values.map {
            PeriodGeographySummary(name: $0.name, code: $0.code, visitCount: $0.count)
        }.sorted {
            if $0.visitCount != $1.visitCount { return $0.visitCount > $1.visitCount }
            return $0.name < $1.name
        }
    }

    private static func representativePhotos(
        _ references: [PhotoReference],
        metadata: [String: PeriodPhotoMetadata]
    ) -> [PhotoReference] {
        let unique = Dictionary(grouping: references, by: \.id).compactMap {
            $0.value.min { $0.addedAt < $1.addedAt }
        }.sorted {
            let lhsDate = metadata[$0.id]?.creationDate ?? $0.addedAt
            let rhsDate = metadata[$1.id]?.creationDate ?? $1.addedAt
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return $0.id < $1.id
        }
        guard unique.count > 4 else { return unique }
        let favorites = unique.filter { metadata[$0.id]?.isFavorite == true }
        var selected = Array(favorites.prefix(4))
        let remaining = unique.filter { reference in
            !selected.contains { $0.id == reference.id }
        }
        let needed = 4 - selected.count
        if needed > 0, !remaining.isEmpty {
            selected.append(contentsOf: (0..<needed).map { index in
                guard needed > 1 else { return remaining[remaining.count / 2] }
                return remaining[index * (remaining.count - 1) / (needed - 1)]
            })
        }
        return selected
    }

    private static func sleepSummary(
        _ entries: [AttributedEntry]
    ) -> PeriodSleepSummary? {
        let samples = entries.compactMap { entry -> (Int, Double?)? in
            guard entry.snapshot.kind == .wakeUp,
                  let wake = entry.snapshot.endTime else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone(
                entry.snapshot.endTimeZoneIdentifier,
                fallback: entry.snapshot.creationTimeZoneIdentifier
            )
            let components = calendar.dateComponents([.hour, .minute], from: wake)
            return ((components.hour ?? 0) * 60 + (components.minute ?? 0),
                    entry.snapshot.wakeUpSleepDurationSeconds)
        }
        guard samples.count >= 3 else { return nil }
        let radians = samples.map { Double($0.0) / 1_440 * 2 * Double.pi }
        let x = radians.map(cos).reduce(0, +) / Double(radians.count)
        let y = radians.map(sin).reduce(0, +) / Double(radians.count)
        var angle = atan2(y, x)
        if angle < 0 { angle += 2 * Double.pi }
        let averageMinute = Int((angle / (2 * Double.pi) * 1_440).rounded()) % 1_440
        let deviations = samples.map { sample in
            let raw = abs(sample.0 - averageMinute)
            return min(raw, 1_440 - raw)
        }
        let durations = samples.compactMap(\.1)
        return PeriodSleepSummary(
            sampleCount: samples.count,
            averageWakeMinute: averageMinute,
            averageDuration: durations.isEmpty
                ? nil : durations.reduce(0, +) / Double(durations.count),
            consistencyMinutes: deviations.reduce(0, +) / deviations.count
        )
    }

    private static func longestJourney(
        _ entries: [AttributedEntry]
    ) -> PeriodJourneySummary? {
        entries.compactMap { entry -> PeriodJourneySummary? in
            let snapshot = entry.snapshot
            let distance: Double?
            let origin: String
            let destination: String
            if snapshot.kind == .transit {
                distance = snapshot.transitDistanceMeters
                origin = snapshot.origin
                destination = snapshot.destination
            } else if snapshot.kind == .workout,
                      snapshot.workoutMovementKind == .moving {
                distance = snapshot.workoutDistanceMeters
                origin = snapshot.workoutOrigin
                destination = snapshot.workoutDestination
            } else { return nil }
            guard let distance, distance >= 100_000,
                  let occurrence = entry.occurrence else { return nil }
            return PeriodJourneySummary(
                day: entry.day,
                distanceMeters: distance,
                originName: origin,
                destinationName: destination,
                mapData: TimelineOverviewData.make(occurrences: [occurrence]),
                representativeEntryID: occurrence.entryID,
                workoutUUID: snapshot.kind == .workout
                    ? snapshot.workoutUUID : nil
            )
        }.sorted {
            if $0.distanceMeters != $1.distanceMeters {
                return $0.distanceMeters > $1.distanceMeters
            }
            if $0.day != $1.day { return $0.day < $1.day }
            return ($0.representativeEntryID?.uuidString ?? "")
                < ($1.representativeEntryID?.uuidString ?? "")
        }.first
    }

    private static func activity(
        for key: PeriodSummaryKey,
        entries: [AttributedEntry]
    ) -> [Int] {
        switch key {
        case .month(let month):
            let calendar = Calendar(identifier: .gregorian)
            let date = calendar.date(from: DateComponents(
                year: month.year,
                month: month.month,
                day: 1
            )) ?? .now
            let count = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
            var result = Array(repeating: 0, count: count)
            for entry in entries where entry.day.day <= count {
                result[entry.day.day - 1] += 1
            }
            return result
        case .year:
            var result = Array(repeating: 0, count: 12)
            for entry in entries { result[entry.day.month - 1] += 1 }
            return result
        }
    }

    private static func newGroundCount(
        key: PeriodSummaryKey,
        entries: [AttributedEntry],
        allEntries: [AttributedEntry]
    ) -> Int {
        guard case .year(let year) = key else { return 0 }
        let firstYear = Dictionary(grouping: allEntries.flatMap { entry in
            geographicLocations(entry.snapshot).map {
                (locationIdentity($0), entry.day.year)
            }
        }, by: \.0).compactMapValues { $0.map(\.1).min() }
        let identities = Set(entries.flatMap { geographicLocations($0.snapshot) }
            .map(locationIdentity))
        return identities.filter { firstYear[$0] == year.year }.count
    }

    private static func geographicLocations(
        _ snapshot: TimelineEntrySnapshot
    ) -> [TimelineLocationSnapshot] {
        switch snapshot.kind {
        case .transit:
            [snapshot.originLocation, snapshot.destinationLocation].compactMap { $0 }
        case .placeVisit:
            [snapshot.visitLocation].compactMap { $0 }
        case .workout where snapshot.workoutMovementKind == .moving:
            [snapshot.workoutOriginLocation, snapshot.workoutDestinationLocation]
                .compactMap { $0 }
        case .workout:
            [snapshot.workoutPlaceLocation].compactMap { $0 }
        case .wakeUp:
            []
        }
    }

    private static func interval(_ snapshot: TimelineEntrySnapshot) -> DateInterval? {
        guard let start = snapshot.startTime,
              let end = snapshot.endTime, end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    private static func duration(_ snapshot: TimelineEntrySnapshot) -> TimeInterval {
        interval(snapshot)?.duration ?? 0
    }

    private static func unionDuration(_ intervals: [DateInterval]) -> TimeInterval {
        let sorted = intervals.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return 0 }
        var total: TimeInterval = 0
        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(
                    start: current.start,
                    end: max(current.end, interval.end)
                )
            } else {
                total += current.duration
                current = interval
            }
        }
        return total + current.duration
    }

    nonisolated private static func locationIdentity(
        _ location: TimelineLocationSnapshot
    ) -> String {
        if let savedPlaceID = location.savedPlaceID {
            return "place-\(savedPlaceID.uuidString)"
        }
        return String(format: "geo-%.3f-%.3f", location.latitude, location.longitude)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func zone(_ identifier: String, fallback: String) -> TimeZone {
        TimeZone(identifier: identifier)
            ?? TimeZone(identifier: fallback)
            ?? .current
    }
}

nonisolated private extension PeriodSummaryKey {
    var yearValue: Int? {
        guard case .year(let key) = self else { return nil }
        return key.year
    }
}
