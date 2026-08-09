//
//  EntryWeather.swift
//  Journal
//

import Foundation

struct EntryWeather: Codable, Hashable, Sendable {
    var condition: String
    var symbolName: String
    var temperatureCelsius: Double
    var humidity: Double
    var date: Date

    var temperature: Measurement<UnitTemperature> {
        Measurement(value: temperatureCelsius, unit: .celsius)
    }
}

/// The last successful daily WeatherKit result. Entry weather remains the
/// point-in-time observation for the entry itself; this is the durable cache
/// used by day summaries while current and future forecasts refresh.
struct PersistedDayWeather: Codable, Hashable, Sendable {
    var year: Int
    var month: Int
    var day: Int
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String
    var weather: EntryWeather
    /// `nil` represents records written before provisional forecasts were
    /// persisted, when every stored record belonged to a completed day.
    var isFinal: Bool? = nil
}
