//
//  EntryWeatherService.swift
//  Journal
//

import CoreLocation
import Foundation
import SwiftData
import WeatherKit

struct EntryWeatherRequest: Hashable, Sendable {
    let date: Date
    let latitude: Double
    let longitude: Double
}

enum EntryWeatherEndpoint: String, CaseIterable, Hashable, Sendable {
    case start
    case end
}

struct EntryWeatherAttribution: Equatable, Sendable {
    let lightMarkURL: URL
    let darkMarkURL: URL
    let legalPageURL: URL
}

private enum EntryWeatherServiceError: LocalizedError {
    case noHourlyWeather
    case noDailyWeather

    var errorDescription: String? {
        switch self {
        case .noHourlyWeather:
            String(localized: "Weather is unavailable for this time and location.")
        case .noDailyWeather:
            String(localized: "Weather is unavailable for this day and location.")
        }
    }
}

nonisolated protocol DayWeatherProviding: Sendable {
    func weather(for request: DayWeatherRequest) async throws
        -> DayWeatherSummary
}

actor WeatherKitDayClient: DayWeatherProviding {
    typealias Loader = @Sendable (DayWeatherRequest) async throws
        -> DayWeatherSummary

    nonisolated static let shared = WeatherKitDayClient()

    private let service = WeatherService.shared
    private let loader: Loader?
    private var cache: [DayWeatherRequest: DayWeatherSummary] = [:]
    private var tasks: [
        DayWeatherRequest: Task<DayWeatherSummary, any Error>
    ] = [:]

    init(loader: Loader? = nil) {
        self.loader = loader
    }

    func weather(for request: DayWeatherRequest) async throws
        -> DayWeatherSummary {
        let retainsResult = request.isCompleted()
        if retainsResult, let cached = cache[request] {
            return cached
        }
        if let task = tasks[request] {
            return try await task.value
        }

        let loader = loader
        let service = service
        let task = Task<DayWeatherSummary, any Error> {
            if let loader {
                return try await loader(request)
            }
            let location = CLLocation(
                latitude: request.latitude,
                longitude: request.longitude
            )
            let forecast = try await service.weather(
                for: location,
                including: .daily(
                    startDate: request.startDate,
                    endDate: request.endDate
                )
            )
            guard let day = forecast.min(by: {
                abs($0.date.timeIntervalSince(request.startDate))
                    < abs($1.date.timeIntervalSince(request.startDate))
            }) else {
                throw EntryWeatherServiceError.noDailyWeather
            }
            return DayWeatherSummary(
                condition: day.condition.rawValue,
                symbolName: day.symbolName,
                highTemperatureCelsius: day.highTemperature
                    .converted(to: .celsius).value,
                maximumHumidity: day.maximumHumidity,
                date: day.date
            )
        }
        tasks[request] = task

        do {
            let result = try await task.value
            if retainsResult {
                cache[request] = result
            }
            tasks[request] = nil
            return result
        } catch {
            tasks[request] = nil
            throw error
        }
    }
}

actor WeatherKitEntryClient {
    static let shared = WeatherKitEntryClient()

    private let service = WeatherService.shared
    private var cachedAttribution: EntryWeatherAttribution?

    func weather(for request: EntryWeatherRequest) async throws -> EntryWeather {
        let location = CLLocation(
            latitude: request.latitude,
            longitude: request.longitude
        )
        let forecast = try await service.weather(
            for: location,
            including: .hourly(
                startDate: request.date.addingTimeInterval(-60 * 60),
                endDate: request.date.addingTimeInterval(60 * 60)
            )
        )
        guard let hour = forecast.min(by: {
            abs($0.date.timeIntervalSince(request.date))
                < abs($1.date.timeIntervalSince(request.date))
        }) else {
            throw EntryWeatherServiceError.noHourlyWeather
        }

        return EntryWeather(
            condition: hour.condition.rawValue,
            symbolName: hour.symbolName,
            temperatureCelsius: hour.temperature.converted(to: .celsius).value,
            humidity: hour.humidity,
            date: hour.date
        )
    }

    func attribution() async throws -> EntryWeatherAttribution {
        if let cachedAttribution {
            return cachedAttribution
        }

        let attribution = try await service.attribution
        let snapshot = EntryWeatherAttribution(
            lightMarkURL: attribution.combinedMarkLightURL,
            darkMarkURL: attribution.combinedMarkDarkURL,
            legalPageURL: attribution.legalPageURL
        )
        cachedAttribution = snapshot
        return snapshot
    }
}

@MainActor
enum EntryWeatherService {
    static func request(for entry: LogEntry) -> EntryWeatherRequest? {
        request(for: entry, endpoint: .start)
    }

    static func request(
        for entry: LogEntry,
        endpoint: EntryWeatherEndpoint
    ) -> EntryWeatherRequest? {
        let date = switch endpoint {
        case .start: entry.startTime
        case .end: entry.endTime
        }
        guard let date,
              let location = resolvedLocation(for: entry, endpoint: endpoint) else {
            return nil
        }

        return EntryWeatherRequest(
            date: date,
            latitude: location.latitude,
            longitude: location.longitude
        )
    }

    @discardableResult
    static func populate(
        _ entry: LogEntry,
        in modelContext: ModelContext,
        force: Bool = false,
        endpoint: EntryWeatherEndpoint = .start
    ) async throws -> Bool {
        let entryID = entry.id
        return try await populate(
            entryID: entryID,
            in: modelContext,
            force: force,
            endpoint: endpoint
        )
    }

    @discardableResult
    static func populate(
        entryID: UUID,
        in modelContext: ModelContext,
        force: Bool = false,
        endpoint: EntryWeatherEndpoint = .start
    ) async throws -> Bool {
        guard let entry = try entry(withID: entryID, in: modelContext) else {
            return false
        }
        let existingWeather = switch endpoint {
        case .start: entry.weather
        case .end: entry.endWeather
        }
        guard force || existingWeather == nil else { return true }
        guard let request = request(for: entry, endpoint: endpoint) else {
            return false
        }

        let weather = try await WeatherKitEntryClient.shared.weather(
            for: request
        )

        guard let currentEntry = try self.entry(
            withID: entryID,
            in: modelContext
        ), request == self.request(for: currentEntry, endpoint: endpoint) else {
            return false
        }
        switch endpoint {
        case .start: currentEntry.weather = weather
        case .end: currentEntry.endWeather = weather
        }
        try modelContext.save()
        return true
    }

    static func populateEndpoints(
        _ entry: LogEntry,
        in modelContext: ModelContext,
        force: Bool = false
    ) async {
        await populateEndpoints(
            entryID: entry.id,
            in: modelContext,
            force: force
        )
    }

    static func populateEndpoints(
        entryID: UUID,
        in modelContext: ModelContext,
        force: Bool = false
    ) async {
        for endpoint in EntryWeatherEndpoint.allCases {
            do {
                _ = try await populate(
                    entryID: entryID,
                    in: modelContext,
                    force: force,
                    endpoint: endpoint
                )
            } catch {
                print("WeatherKit \(endpoint.rawValue) lookup failed: \(error)")
            }
        }
    }

    static func refreshInBackground(
        _ entry: LogEntry,
        in modelContext: ModelContext
    ) {
        let entryID = entry.id
        let container = modelContext.container
        Task {
            let enrichmentContext = ModelContext(container)
            enrichmentContext.autosaveEnabled = false
            await populateEndpoints(
                entryID: entryID,
                in: enrichmentContext,
                force: true
            )
        }
    }

    static func populateMissing(in modelContext: ModelContext) async {
        let entryIDs: [UUID]
        do {
            entryIDs = try modelContext.fetch(FetchDescriptor<LogEntry>())
                .compactMap { entry in
                    entry.weather == nil || entry.endWeather == nil
                        ? entry.id
                        : nil
                }
        } catch {
            print("Could not load entries for WeatherKit enrichment: \(error)")
            return
        }

        for entryID in entryIDs {
            await populateEndpoints(entryID: entryID, in: modelContext)
        }
    }

    private static func entry(
        withID entryID: UUID,
        in modelContext: ModelContext
    ) throws -> LogEntry? {
        var descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.id == entryID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func resolvedLocation(
        for entry: LogEntry,
        endpoint: EntryWeatherEndpoint
    ) -> Location? {
        switch entry.kind {
        case .transit:
            switch endpoint {
            case .start:
                entry.transitDetails?.originLocation
                    ?? entry.transitDetails?.originPlace?.location
            case .end:
                entry.transitDetails?.destinationLocation
                    ?? entry.transitDetails?.destinationPlace?.location
            }
        case .placeVisit:
            entry.placeVisitDetails?.location
                ?? entry.placeVisitDetails?.place?.location
        case .workout:
            if entry.workoutDetails?.movementKind == .moving {
                switch endpoint {
                case .start:
                    entry.workoutDetails?.originLocation
                        ?? entry.workoutDetails?.originPlace?.location
                case .end:
                    entry.workoutDetails?.destinationLocation
                        ?? entry.workoutDetails?.destinationPlace?.location
                }
            } else {
                entry.workoutDetails?.sourceLocation
                    ?? entry.workoutDetails?.place?.location
            }
        case .wakeUp:
            nil
        }
    }
}
