import Foundation
import Observation
import SwiftData

nonisolated enum DayWeatherLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(DayWeatherSummary)
    case unavailable
}

nonisolated protocol DayWorkoutRouteProviding: Sendable {
    func route(for workoutUUID: UUID) async throws
        -> [WorkoutCoordinateSnapshot]
}

actor HealthKitDayWorkoutRouteClient: DayWorkoutRouteProviding {
    typealias Loader = @Sendable (UUID) async throws
        -> [WorkoutCoordinateSnapshot]

    nonisolated static let shared = HealthKitDayWorkoutRouteClient()

    private let loader: Loader?
    private var cache: [UUID: [WorkoutCoordinateSnapshot]] = [:]
    private var tasks: [
        UUID: Task<[WorkoutCoordinateSnapshot], any Error>
    ] = [:]

    init(loader: Loader? = nil) {
        self.loader = loader
    }

    func route(for workoutUUID: UUID) async throws
        -> [WorkoutCoordinateSnapshot] {
        if let cached = cache[workoutUUID] {
            return cached
        }
        if let task = tasks[workoutUUID] {
            return try await task.value
        }

        let loader = loader
        let task = Task<[WorkoutCoordinateSnapshot], any Error> {
            if let loader {
                return try await loader(workoutUUID)
            }
            return try await HealthKitWorkoutClient.shared.exactRoute(
                for: workoutUUID
            )
        }
        tasks[workoutUUID] = task

        do {
            let points = try await task.value
            cache[workoutUUID] = points
            tasks[workoutUUID] = nil
            return points
        } catch {
            tasks[workoutUUID] = nil
            throw error
        }
    }
}

private enum SummaryRouteGeometry {
    static let maximumPointCount = 160

    static func samples<Element>(_ values: [Element]) -> [Element] {
        guard values.count > maximumPointCount else { return values }
        let lastIndex = values.count - 1
        return (0..<maximumPointCount).map { index in
            values[index * lastIndex / (maximumPointCount - 1)]
        }
    }
}

@MainActor
@Observable
final class DaySummaryRowModel: Identifiable {
    let summary: DaySummary
    private(set) var overviewData: TimelineOverviewData
    private(set) var weatherState: DayWeatherLoadState = .idle

    @ObservationIgnored
    private var didLoadRoutes = false

    @ObservationIgnored
    private var persistWeather: ((DayWeatherRequest, DayWeatherSummary) -> Void)?

    var id: TimelineDayKey { summary.day }

    init(
        summary: DaySummary,
        weatherState: DayWeatherLoadState = .idle,
        persistWeather: ((DayWeatherRequest, DayWeatherSummary) -> Void)? = nil
    ) {
        self.summary = summary
        overviewData = summary.overviewData
        self.weatherState = weatherState
        self.persistWeather = persistWeather
    }

    func prepareForReload(
        persistedWeather: DayWeatherSummary?,
        persistWeather: ((DayWeatherRequest, DayWeatherSummary) -> Void)?
    ) {
        self.persistWeather = persistWeather
        if let persistedWeather {
            weatherState = .loaded(persistedWeather)
        } else if weatherState != .loading {
            // The current day is intentionally volatile, and failed completed
            // requests should be eligible for another attempt after a reload.
            weatherState = .idle
        }
    }

    func loadEnrichment() async {
        await loadEnrichment(
            weatherClient: WeatherKitDayClient.shared,
            routeClient: HealthKitDayWorkoutRouteClient.shared
        )
    }

    func loadMapEnrichment() async {
        await loadRoutes(using: HealthKitDayWorkoutRouteClient.shared)
    }

    func loadEnrichment(
        weatherClient: any DayWeatherProviding,
        routeClient: any DayWorkoutRouteProviding
    ) async {
        async let weather: Void = loadWeather(using: weatherClient)
        async let routes: Void = loadRoutes(using: routeClient)
        _ = await (weather, routes)
    }

    private func loadWeather(
        using client: any DayWeatherProviding
    ) async {
        guard weatherState == .idle,
              let request = summary.weatherRequest else { return }
        weatherState = .loading
        do {
            let weather = try await client.weather(for: request)
            guard !Task.isCancelled else {
                weatherState = .idle
                return
            }
            weatherState = .loaded(weather)
            if request.isCompleted() {
                persistWeather?(request, weather)
            }
        } catch is CancellationError {
            weatherState = .idle
        } catch {
            weatherState = .unavailable
        }
    }

    private func loadRoutes(
        using client: any DayWorkoutRouteProviding
    ) async {
        guard !didLoadRoutes else { return }
        didLoadRoutes = true
        let requests = summary.occurrences.compactMap {
            occurrence -> (UUID, UUID)? in
            guard occurrence.snapshot.workoutMovementKind == .moving,
                  let workoutUUID = occurrence.snapshot.workoutUUID else {
                return nil
            }
            return (occurrence.entryID, workoutUUID)
        }
        guard !requests.isEmpty else { return }

        var routes: [UUID: [WorkoutCoordinateSnapshot]] = [:]
        for (entryID, workoutUUID) in requests {
            guard !Task.isCancelled else {
                didLoadRoutes = false
                return
            }
            do {
                let points = try await client.route(for: workoutUUID)
                if points.count > 1 {
                    routes[entryID] = SummaryRouteGeometry.samples(points)
                }
            } catch is CancellationError {
                didLoadRoutes = false
                return
            } catch {
                continue
            }
        }
        guard !Task.isCancelled else {
            didLoadRoutes = false
            return
        }
        overviewData = TimelineOverviewData.make(
            occurrences: summary.occurrences.filter {
                $0.role != .unresolvedReview
            },
            workoutRoutes: routes
        )
    }
}

@MainActor
@Observable
final class HomeFeedModel {
    private(set) var rows: [DaySummaryRowModel] = []
    private(set) var monthRows: [PeriodSummaryRowModel] = []
    private(set) var yearRows: [PeriodSummaryRowModel] = []
    private(set) var errorMessage: String?
    private(set) var mapSnapshotRevision = 0

    var days: [TimelineDayKey] { rows.map(\.id) }

    func reload(in modelContext: ModelContext) {
        do {
            let entries = try modelContext.fetch(
                FetchDescriptor<LogEntry>(
                    sortBy: [SortDescriptor(\LogEntry.createdAt)]
                )
            )
            let snapshots = entries.map(TimelineEntrySnapshot.init)
            let summaries = DaySummaryProjector.makeSummaries(entries: snapshots)
            let photoMetadata = PeriodPhotoMetadataService.metadata(
                for: snapshots.flatMap(\.photoReferences)
            )
            let existingRows = Dictionary(
                uniqueKeysWithValues: rows.map { ($0.id, $0) }
            )
            let entriesByID = Dictionary(
                uniqueKeysWithValues: entries.map { ($0.id, $0) }
            )
            rows = summaries.map { summary in
                let persistedWeather = persistedWeather(
                    for: summary,
                    entriesByID: entriesByID
                )
                let persistence = weatherPersistence(
                    for: summary,
                    entriesByID: entriesByID,
                    modelContext: modelContext
                )
                if let existing = existingRows[summary.day],
                   existing.summary == summary {
                    existing.prepareForReload(
                        persistedWeather: persistedWeather,
                        persistWeather: persistence
                    )
                    return existing
                }
                return DaySummaryRowModel(
                    summary: summary,
                    weatherState: persistedWeather.map {
                        .loaded($0)
                    } ?? .idle,
                    persistWeather: persistence
                )
            }
            monthRows = stablePeriodRows(
                PeriodSummaryProjector.makeMonthSummaries(
                    entries: snapshots,
                    daySummaries: summaries,
                    photoMetadata: photoMetadata
                ),
                existing: monthRows
            )
            yearRows = stablePeriodRows(
                PeriodSummaryProjector.makeYearSummaries(
                    entries: snapshots,
                    daySummaries: summaries,
                    photoMetadata: photoMetadata
                ),
                existing: yearRows
            )
            mapSnapshotRevision &+= 1
            errorMessage = nil
        } catch {
            rows = []
            monthRows = []
            yearRows = []
            errorMessage = error.localizedDescription
        }
    }

    func nearestDay(to target: TimelineDayKey) -> TimelineDayKey? {
        DaySummaryProjector.nearestDay(to: target, in: days)
    }

    func firstDay(in month: MonthKey) -> TimelineDayKey? {
        days.first { MonthKey(day: $0) == month }
    }

    func firstMonth(in year: YearKey) -> MonthKey? {
        monthRows.compactMap(\.summary.monthKey).first { $0.year == year.year }
    }

    private func stablePeriodRows(
        _ summaries: [PeriodSummary],
        existing: [PeriodSummaryRowModel]
    ) -> [PeriodSummaryRowModel] {
        let existingByID = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.id, $0) }
        )
        return summaries.map { summary in
            if let row = existingByID[summary.id], row.summary == summary {
                return row
            }
            return PeriodSummaryRowModel(summary: summary)
        }
    }

    private func persistedWeather(
        for summary: DaySummary,
        entriesByID: [UUID: LogEntry]
    ) -> DayWeatherSummary? {
        guard let request = summary.weatherRequest,
              request.isCompleted() else { return nil }
        for occurrence in summary.occurrences {
            guard let entry = entriesByID[occurrence.entryID],
                  let record = entry.dayWeatherRecords.first(where: {
                      $0.matches(request)
                  }) else {
                continue
            }
            return record.summary
        }
        return nil
    }

    private func weatherPersistence(
        for summary: DaySummary,
        entriesByID: [UUID: LogEntry],
        modelContext: ModelContext
    ) -> ((DayWeatherRequest, DayWeatherSummary) -> Void)? {
        guard let storageEntry = summary.occurrences.lazy.compactMap({
            entriesByID[$0.entryID]
        }).first else {
            return nil
        }
        return { request, weather in
            guard request.isCompleted() else { return }
            let record = PersistedDayWeather(
                request: request,
                summary: weather
            )
            storageEntry.dayWeatherRecords.removeAll {
                $0.year == record.year
                    && $0.month == record.month
                    && $0.day == record.day
            }
            storageEntry.dayWeatherRecords.append(record)
            do {
                try modelContext.save()
            } catch {
                print("Could not persist daily weather: \(error)")
            }
        }
    }
}

@MainActor
@Observable
final class PeriodSummaryRowModel: Identifiable {
    let summary: PeriodSummary
    let layoutRecipe: PeriodSummaryLayoutRecipe
    private(set) var overviewData: TimelineOverviewData
    private(set) var frequentRouteData: TimelineOverviewData?
    private(set) var longestJourneyData: TimelineOverviewData?

    @ObservationIgnored
    private var didLoadRoute = false

    var id: PeriodSummaryKey { summary.id }

    init(summary: PeriodSummary) {
        self.summary = summary
        layoutRecipe = PeriodSummaryLayoutRecipe.make(for: summary)
        overviewData = summary.overviewData
        frequentRouteData = summary.frequentRoute?.mapData
        longestJourneyData = summary.longestJourney?.mapData
    }

    func loadEnrichment() async {
        guard !didLoadRoute else { return }
        didLoadRoute = true
        var requests: [(entryID: UUID, workoutUUID: UUID, distance: Double)] = []
        var seen: Set<UUID> = []
        for occurrence in summary.days.flatMap(\.occurrences) {
            guard seen.insert(occurrence.entryID).inserted,
                  occurrence.snapshot.workoutMovementKind == .moving,
                  let workoutUUID = occurrence.snapshot.workoutUUID else {
                continue
            }
            requests.append((
                occurrence.entryID,
                workoutUUID,
                occurrence.snapshot.workoutDistanceMeters ?? 0
            ))
        }
        guard !requests.isEmpty else { return }

        guard let longest = requests.max(by: { $0.distance < $1.distance }) else {
            return
        }
        var selected = [longest]
        if let routeEntryID = summary.frequentRoute?.representativeEntryID,
           let frequent = requests.first(where: { $0.entryID == routeEntryID }),
           frequent.entryID != longest.entryID {
            selected.append(frequent)
        }

        for request in selected {
            do {
                let points = try await HealthKitDayWorkoutRouteClient.shared.route(
                    for: request.workoutUUID
                )
                guard points.count > 1, !Task.isCancelled else {
                    didLoadRoute = !Task.isCancelled
                    return
                }
                overviewData = replacingWorkoutPath(
                    in: overviewData,
                    entryID: request.entryID,
                    points: points
                )
                if summary.frequentRoute?.representativeEntryID == request.entryID,
                   let data = frequentRouteData {
                    frequentRouteData = replacingWorkoutPath(
                        in: data,
                        entryID: request.entryID,
                        points: points
                    )
                }
                if summary.longestJourney?.representativeEntryID == request.entryID,
                   let data = longestJourneyData {
                    longestJourneyData = replacingWorkoutPath(
                        in: data,
                        entryID: request.entryID,
                        points: points
                    )
                }
            } catch is CancellationError {
                didLoadRoute = false
                return
            } catch {
                continue
            }
        }
    }

    private func replacingWorkoutPath(
        in data: TimelineOverviewData,
        entryID: UUID,
        points: [WorkoutCoordinateSnapshot]
    ) -> TimelineOverviewData {
        var paths = data.paths.filter { $0.id != entryID }
        let displayPoints = SummaryRouteGeometry.samples(points)
        paths.append(TimelineMapPath(
            id: entryID,
            kind: .workout,
            coordinates: displayPoints.map(\.coordinate)
        ))
        return TimelineOverviewData(markers: data.markers, paths: paths)
    }
}
