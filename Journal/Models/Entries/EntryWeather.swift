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
