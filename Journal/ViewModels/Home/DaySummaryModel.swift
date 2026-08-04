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

@MainActor
@Observable
final class DaySummaryRowModel: Identifiable {
    let summary: DaySummary
    private(set) var overviewData: TimelineOverviewData
    private(set) var weatherState: DayWeatherLoadState = .idle

    @ObservationIgnored
    private var didLoadRoutes = false

    var id: TimelineDayKey { summary.day }

    init(
        summary: DaySummary,
        weatherState: DayWeatherLoadState = .idle
    ) {
        self.summary = summary
        overviewData = summary.overviewData
        self.weatherState = weatherState
    }

    func loadEnrichment() async {
        await loadEnrichment(
            weatherClient: WeatherKitDayClient.shared,
            routeClient: HealthKitDayWorkoutRouteClient.shared
        )
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
                    routes[entryID] = points
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
    private(set) var errorMessage: String?

    var days: [TimelineDayKey] { rows.map(\.id) }

    func reload(in modelContext: ModelContext) {
        do {
            let entries = try modelContext.fetch(
                FetchDescriptor<LogEntry>(
                    sortBy: [SortDescriptor(\LogEntry.createdAt)]
                )
            )
            let summaries = DaySummaryProjector.makeSummaries(
                entries: entries.map(TimelineEntrySnapshot.init)
            )
            let existingRows = Dictionary(
                uniqueKeysWithValues: rows.map { ($0.id, $0) }
            )
            rows = summaries.map { summary in
                if let existing = existingRows[summary.day],
                   existing.summary == summary {
                    return existing
                }
                return DaySummaryRowModel(summary: summary)
            }
            errorMessage = nil
        } catch {
            rows = []
            errorMessage = error.localizedDescription
        }
    }

    func nearestDay(to target: TimelineDayKey) -> TimelineDayKey? {
        DaySummaryProjector.nearestDay(to: target, in: days)
    }
}
