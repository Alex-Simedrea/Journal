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

struct EntryWeatherAttribution: Equatable, Sendable {
    let lightMarkURL: URL
    let darkMarkURL: URL
    let legalPageURL: URL
}

private enum EntryWeatherServiceError: LocalizedError {
    case noHourlyWeather

    var errorDescription: String? {
        switch self {
        case .noHourlyWeather:
            String(localized: "Weather is unavailable for this time and location.")
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
        guard let date = entry.startTime,
              let location = resolvedLocation(for: entry) else {
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
        force: Bool = false
    ) async throws -> Bool {
        guard force || entry.weather == nil else { return true }
        guard let request = request(for: entry) else { return false }

        let weather = try await WeatherKitEntryClient.shared.weather(
            for: request
        )

        guard request == self.request(for: entry) else { return false }
        entry.weather = weather
        try modelContext.save()
        return true
    }

    static func refreshInBackground(
        _ entry: LogEntry,
        in modelContext: ModelContext
    ) {
        Task {
            do {
                try await populate(entry, in: modelContext, force: true)
            } catch {
                print("WeatherKit entry lookup failed: \(error)")
            }
        }
    }

    static func populateMissing(in modelContext: ModelContext) async {
        let entries: [LogEntry]
        do {
            entries = try modelContext.fetch(FetchDescriptor<LogEntry>())
        } catch {
            print("Could not load entries for WeatherKit enrichment: \(error)")
            return
        }

        for entry in entries where entry.weather == nil {
            do {
                try await populate(entry, in: modelContext)
            } catch {
                print("WeatherKit entry lookup failed: \(error)")
            }
        }
    }

    private static func resolvedLocation(for entry: LogEntry) -> Location? {
        switch entry.kind {
        case .transit:
            entry.transitDetails?.originLocation
                ?? entry.transitDetails?.originPlace?.location
        case .placeVisit:
            entry.placeVisitDetails?.location
                ?? entry.placeVisitDetails?.place?.location
        case .workout:
            if entry.workoutDetails?.movementKind == .moving {
                entry.workoutDetails?.originLocation
                    ?? entry.workoutDetails?.originPlace?.location
            } else {
                entry.workoutDetails?.sourceLocation
                    ?? entry.workoutDetails?.place?.location
            }
        case .wakeUp:
            nil
        }
    }
}
