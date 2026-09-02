import Foundation
import Observation
import SwiftData

nonisolated enum DayWeatherLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(DayWeatherSummary)
    case refreshing(DayWeatherSummary)
    case unavailable

    var summary: DayWeatherSummary? {
        switch self {
        case .loaded(let summary), .refreshing(let summary): summary
        case .idle, .loading, .unavailable: nil
        }
    }
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
    private let cacheDirectory: URL
    private var cache: [UUID: [WorkoutCoordinateSnapshot]] = [:]
    private var tasks: [
        UUID: Task<[WorkoutCoordinateSnapshot], any Error>
    ] = [:]

    init(loader: Loader? = nil, cacheDirectory: URL? = nil) {
        self.loader = loader
        let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        self.cacheDirectory = cacheDirectory ?? caches.appending(
            path: "DayWorkoutRoutes-v1",
            directoryHint: .isDirectory
        )
    }

    func route(for workoutUUID: UUID) async throws
        -> [WorkoutCoordinateSnapshot] {
        if let cached = cache[workoutUUID] {
            return cached
        }
        if let persisted = persistedRoute(for: workoutUUID) {
            cache[workoutUUID] = persisted
            return persisted
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
            let points = SummaryRouteGeometry.samples(try await task.value)
            cache[workoutUUID] = points
            tasks[workoutUUID] = nil
            if points.count > 1 {
                persist(points, for: workoutUUID)
            }
            return points
        } catch {
            tasks[workoutUUID] = nil
            throw error
        }
    }

    private func persistedRoute(
        for workoutUUID: UUID
    ) -> [WorkoutCoordinateSnapshot]? {
        guard let data = try? Data(contentsOf: fileURL(for: workoutUUID)),
              let points = try? JSONDecoder().decode(
                [WorkoutCoordinateSnapshot].self,
                from: data
              ),
              points.count > 1 else { return nil }
        return points
    }

    private func persist(
        _ points: [WorkoutCoordinateSnapshot],
        for workoutUUID: UUID
    ) {
        do {
            try FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(points)
            try data.write(to: fileURL(for: workoutUUID), options: .atomic)
        } catch {
            // HealthKit remains the source of truth. A cache write failure only
            // means the route will be queried again on a later launch.
        }
    }

    private func fileURL(for workoutUUID: UUID) -> URL {
        cacheDirectory
            .appending(path: workoutUUID.uuidString.lowercased())
            .appendingPathExtension("json")
    }
}

nonisolated private enum SummaryRouteGeometry {
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
    let layoutRecipe: DaySummaryLayoutRecipe
    private(set) var overviewData: TimelineOverviewData
    private(set) var weatherState: DayWeatherLoadState = .idle
    private(set) var enrichmentRevision = 0
    private(set) var isWorkoutRouteEnrichmentPending: Bool

    @ObservationIgnored
    private var didLoadRoutes = false

    @ObservationIgnored
    private var persistWeather: (@Sendable (
        DayWeatherRequest,
        DayWeatherSummary
    ) async -> Void)?

    @ObservationIgnored
    private var needsWeatherRefresh: Bool

    var id: TimelineDayKey { summary.day }

    init(
        summary: DaySummary,
        weatherState: DayWeatherLoadState = .idle,
        needsWeatherRefresh: Bool? = nil,
        persistWeather: (@Sendable (
            DayWeatherRequest,
            DayWeatherSummary
        ) async -> Void)? = nil
    ) {
        self.summary = summary
        layoutRecipe = DaySummaryLayoutRecipe.make(for: summary)
        overviewData = summary.overviewData
        self.weatherState = weatherState
        isWorkoutRouteEnrichmentPending = summary.occurrences.contains {
            $0.snapshot.workoutMovementKind == .moving
                && $0.snapshot.workoutUUID != nil
        }
        self.needsWeatherRefresh = needsWeatherRefresh
            ?? (summary.weatherRequest != nil && weatherState.summary == nil)
        self.persistWeather = persistWeather
    }

    func prepareForReload(
        persistedWeather: DayWeatherSummary?,
        weatherNeedsRefresh: Bool,
        persistWeather: (@Sendable (
            DayWeatherRequest,
            DayWeatherSummary
        ) async -> Void)?
    ) {
        self.persistWeather = persistWeather
        guard weatherState != .loading else { return }
        if case .refreshing = weatherState { return }

        let cachedWeather = weatherState.summary ?? persistedWeather
        needsWeatherRefresh = weatherNeedsRefresh || cachedWeather == nil
        if needsWeatherRefresh {
            weatherState = cachedWeather.map(DayWeatherLoadState.loaded) ?? .idle
            enrichmentRevision &+= 1
        } else if let cachedWeather {
            weatherState = .loaded(cachedWeather)
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
        guard needsWeatherRefresh,
              let request = summary.weatherRequest,
              weatherState != .loading else { return }
        if case .refreshing = weatherState { return }

        let cachedWeather = weatherState.summary
        weatherState = cachedWeather.map(DayWeatherLoadState.refreshing)
            ?? .loading
        needsWeatherRefresh = false
        do {
            let weather = try await client.weather(for: request)
            guard !Task.isCancelled else {
                weatherState = cachedWeather.map(DayWeatherLoadState.loaded)
                    ?? .idle
                needsWeatherRefresh = true
                return
            }
            weatherState = .loaded(weather)
            await persistWeather?(request, weather)
        } catch is CancellationError {
            weatherState = cachedWeather.map(DayWeatherLoadState.loaded)
                ?? .idle
            needsWeatherRefresh = true
        } catch {
            weatherState = cachedWeather.map(DayWeatherLoadState.loaded)
                ?? .unavailable
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
        guard !requests.isEmpty else {
            isWorkoutRouteEnrichmentPending = false
            return
        }

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
        let occurrences = summary.occurrences.filter {
            $0.role != .unresolvedReview
        }
        let projected = await Task.detached(priority: .utility) {
            TimelineOverviewData.make(
                occurrences: occurrences,
                workoutRoutes: routes
            )
        }.value
        guard !Task.isCancelled else {
            didLoadRoutes = false
            return
        }
        overviewData = projected
        isWorkoutRouteEnrichmentPending = false
    }
}

@MainActor
@Observable
final class HomeFeedModel {
    nonisolated private struct MapSlotSource: Equatable, Sendable {
        let id: String
        let fingerprint: Int
    }

    private(set) var rows: [DaySummaryRowModel] = []
    private(set) var monthRows: [PeriodSummaryRowModel] = []
    private(set) var yearRows: [PeriodSummaryRowModel] = []
    private(set) var errorMessage: String?
    private(set) var mapSnapshotRevision = 0

    @ObservationIgnored
    private var mapSlotSources: [MapSlotSource] = []

    @ObservationIgnored
    private var latestSnapshots: [TimelineEntrySnapshot] = []

    @ObservationIgnored
    private var latestDaySummaries: [DaySummary] = []

    @ObservationIgnored
    private var loadedPhotoMetadataIdentifiers: Set<String> = []

    @ObservationIgnored
    private var periodPhotoMetadata: [String: PeriodPhotoMetadata] = [:]

    @ObservationIgnored
    private var periodProjectionRevision = 0

    @ObservationIgnored
    private var periodProjectionTask: Task<Void, Never>?

    var days: [TimelineDayKey] { rows.map(\.id) }

    func reload(in modelContext: ModelContext) async {
        do {
            let store = await JournalPersistenceActors.shared.homeFeed(
                for: JournalModelContainerReference(modelContext.container)
            )
            let projection = try await store.load()
            guard !Task.isCancelled else { return }
            let snapshots = projection.snapshots
            let summaries = projection.daySummaries
            latestSnapshots = snapshots
            latestDaySummaries = summaries
            let existingRows = Dictionary(
                uniqueKeysWithValues: rows.map { ($0.id, $0) }
            )
            rows = summaries.map { summary in
                let persistedWeather = projection.weatherByDay[summary.day]
                let persistence = weatherPersistence(
                    for: summary,
                    storageEntryID: projection
                        .weatherStorageEntryByDay[summary.day],
                    store: store
                )
                if let existing = existingRows[summary.day],
                   existing.summary == summary {
                    existing.prepareForReload(
                        persistedWeather: persistedWeather?.summary,
                        weatherNeedsRefresh: persistedWeather?.needsRefresh
                            ?? (summary.weatherRequest != nil),
                        persistWeather: persistence
                    )
                    return existing
                }
                return DaySummaryRowModel(
                    summary: summary,
                    weatherState: persistedWeather.map {
                        .loaded($0.summary)
                    } ?? .idle,
                    needsWeatherRefresh: persistedWeather?.needsRefresh
                        ?? (summary.weatherRequest != nil),
                    persistWeather: persistence
                )
            }
            await updateMapSnapshotRevision(
                days: summaries,
                periods: (monthRows + yearRows).map(\.summary)
            )
            schedulePeriodProjection(
                snapshots: snapshots,
                daySummaries: summaries,
                photoMetadata: periodPhotoMetadata
            )
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

    func loadPeriodPhotoMetadata() async {
        let references = latestSnapshots.flatMap(\.photoReferences)
        let identifiers = Set(references.map(\.assetLocalIdentifier))
        guard identifiers != loadedPhotoMetadataIdentifiers else {
            await periodProjectionTask?.value
            return
        }

        let metadata = await Task.detached(priority: .utility) {
            PeriodPhotoMetadataService.metadata(for: references)
        }.value
        guard !Task.isCancelled,
              identifiers == Set(
                  latestSnapshots.flatMap(\.photoReferences)
                      .map(\.assetLocalIdentifier)
              ) else { return }

        loadedPhotoMetadataIdentifiers = identifiers
        periodPhotoMetadata = metadata
        schedulePeriodProjection(
            snapshots: latestSnapshots,
            daySummaries: latestDaySummaries,
            photoMetadata: metadata
        )
        await periodProjectionTask?.value
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

    private func schedulePeriodProjection(
        snapshots: [TimelineEntrySnapshot],
        daySummaries: [DaySummary],
        photoMetadata: [String: PeriodPhotoMetadata]
    ) {
        periodProjectionRevision &+= 1
        let revision = periodProjectionRevision
        periodProjectionTask?.cancel()
        periodProjectionTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                (
                    PeriodSummaryProjector.makeMonthSummaries(
                        entries: snapshots,
                        daySummaries: daySummaries,
                        photoMetadata: photoMetadata
                    ),
                    PeriodSummaryProjector.makeYearSummaries(
                        entries: snapshots,
                        daySummaries: daySummaries,
                        photoMetadata: photoMetadata
                    )
                )
            }.value
            guard let self, !Task.isCancelled,
                  revision == periodProjectionRevision else { return }
            monthRows = stablePeriodRows(result.0, existing: monthRows)
            yearRows = stablePeriodRows(result.1, existing: yearRows)
            await updateMapSnapshotRevision(
                days: daySummaries,
                periods: result.0 + result.1
            )
        }
    }

    private func updateMapSnapshotRevision(
        days: [DaySummary],
        periods: [PeriodSummary]
    ) async {
        let sources = await Task.detached(priority: .utility) {
            Self.mapSlotSources(days: days, periods: periods)
        }.value
        guard !Task.isCancelled else { return }
        guard sources != mapSlotSources else { return }
        mapSlotSources = sources
        mapSnapshotRevision &+= 1
    }

    nonisolated private static func mapSlotSources(
        days: [DaySummary],
        periods: [PeriodSummary]
    ) -> [MapSlotSource] {
        days.map {
            MapSlotSource(
                id: "day-\($0.day.id)-overview",
                fingerprint: fingerprint(of: $0.overviewData)
            )
        } + periods.flatMap { summary in
            var result = [
                MapSlotSource(
                    id: "period-\(summary.id.id)-overview",
                    fingerprint: fingerprint(of: summary.overviewData)
                ),
            ]
            if let route = summary.frequentRoute {
                result.append(MapSlotSource(
                    id: "period-\(summary.id.id)-frequent-route",
                    fingerprint: fingerprint(of: route.mapData)
                ))
            }
            if let journey = summary.longestJourney {
                result.append(MapSlotSource(
                    id: "period-\(summary.id.id)-longest-journey",
                    fingerprint: fingerprint(of: journey.mapData)
                ))
            }
            return result
        }
    }

    nonisolated private static func fingerprint(
        of data: TimelineOverviewData
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(data.markers)
        hasher.combine(data.paths)
        switch data.pathDisplayMode {
        case .all: hasher.combine(0)
        case .visibleAtMapScale: hasher.combine(1)
        }
        return hasher.finalize()
    }

    private func weatherPersistence(
        for summary: DaySummary,
        storageEntryID: UUID?,
        store: HomeFeedProjectionStore
    ) -> (@Sendable (DayWeatherRequest, DayWeatherSummary) async -> Void)? {
        guard summary.weatherRequest != nil,
              let storageEntryID else {
            return nil
        }
        return { request, weather in
            do {
                try await store.persistWeather(
                    weather,
                    request: request,
                    entryID: storageEntryID
                )
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
        let summary = summary
        let selected = await Task.detached(priority: .utility) {
            PeriodRouteEnrichmentPlan.requests(for: summary)
        }.value
        guard !Task.isCancelled else {
            didLoadRoute = false
            return
        }
        guard !selected.isEmpty else { return }

        for request in selected {
            do {
                let points = try await HealthKitDayWorkoutRouteClient.shared.route(
                    for: request.workoutUUID
                )
                guard points.count > 1, !Task.isCancelled else {
                    didLoadRoute = !Task.isCancelled
                    return
                }
                let currentOverview = overviewData
                let currentFrequent = frequentRouteData
                let currentLongest = longestJourneyData
                let replacements = await Task.detached(priority: .utility) {
                    (
                        PeriodRouteEnrichmentPlan.replacingWorkoutPath(
                            in: currentOverview,
                            entryID: request.entryID,
                            points: points
                        ),
                        currentFrequent.map {
                            PeriodRouteEnrichmentPlan.replacingWorkoutPath(
                                in: $0,
                                entryID: request.entryID,
                                points: points
                            )
                        },
                        currentLongest.map {
                            PeriodRouteEnrichmentPlan.replacingWorkoutPath(
                                in: $0,
                                entryID: request.entryID,
                                points: points
                            )
                        }
                    )
                }.value
                guard !Task.isCancelled else {
                    didLoadRoute = false
                    return
                }
                overviewData = replacements.0
                if summary.frequentRoute?.representativeEntryID == request.entryID,
                   currentFrequent != nil {
                    frequentRouteData = replacements.1
                }
                if summary.longestJourney?.representativeEntryID == request.entryID,
                   currentLongest != nil {
                    longestJourneyData = replacements.2
                }
            } catch is CancellationError {
                didLoadRoute = false
                return
            } catch {
                continue
            }
        }
    }

}

nonisolated private struct PeriodRouteEnrichmentRequest: Sendable {
    let entryID: UUID
    let workoutUUID: UUID
    let distance: Double
}

nonisolated private enum PeriodRouteEnrichmentPlan {
    static func requests(
        for summary: PeriodSummary
    ) -> [PeriodRouteEnrichmentRequest] {
        var requests: [PeriodRouteEnrichmentRequest] = []
        var seen: Set<UUID> = []
        for occurrence in summary.days.flatMap(\.occurrences) {
            guard seen.insert(occurrence.entryID).inserted,
                  occurrence.snapshot.workoutMovementKind == .moving,
                  let workoutUUID = occurrence.snapshot.workoutUUID else {
                continue
            }
            requests.append(PeriodRouteEnrichmentRequest(
                entryID: occurrence.entryID,
                workoutUUID: workoutUUID,
                distance: occurrence.snapshot.workoutDistanceMeters ?? 0
            ))
        }
        guard let longest = requests.max(by: {
            $0.distance < $1.distance
        }) else { return [] }
        var selected = [longest]
        if let routeEntryID = summary.frequentRoute?.representativeEntryID,
           let frequent = requests.first(where: {
               $0.entryID == routeEntryID
           }),
           frequent.entryID != longest.entryID {
            selected.append(frequent)
        }
        return selected
    }

    static func replacingWorkoutPath(
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
        return TimelineOverviewData(
            markers: data.markers,
            paths: paths,
            pathDisplayMode: data.pathDisplayMode
        )
    }
}
