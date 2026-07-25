import Foundation
import Testing
@testable import Journal

struct WeatherPresentationTests {
    @Test func solarPhaseUsesCoordinateAndHistoricalDate() throws {
        let noon = try Date("2026-03-20T12:00:00Z", strategy: .iso8601)
        let midnight = try Date("2026-03-20T00:00:00Z", strategy: .iso8601)

        #expect(
            WeatherPresentation.skyPhase(
                date: noon,
                latitude: 0,
                longitude: 0,
                symbolName: "sun.max.fill",
                timeZone: .gmt
            ) == .day
        )
        #expect(
            WeatherPresentation.skyPhase(
                date: midnight,
                latitude: 0,
                longitude: 0,
                symbolName: "sun.max.fill",
                timeZone: .gmt
            ) == .night
        )
    }

    @Test func dawnAndDuskHaveDedicatedPalettes() {
        let dawn = WeatherPresentation.gradientHexes(
            symbolName: "sun.max.fill",
            phase: .dawn
        )
        let day = WeatherPresentation.gradientHexes(
            symbolName: "sun.max.fill",
            phase: .day
        )
        let dusk = WeatherPresentation.gradientHexes(
            symbolName: "sun.max.fill",
            phase: .dusk
        )
        let night = WeatherPresentation.gradientHexes(
            symbolName: "moon.stars.fill",
            phase: .night
        )

        #expect(dawn.count == 3)
        #expect(dusk.count == 3)
        #expect(dawn != day)
        #expect(dusk != night)
        #expect(day != night)
    }

    @Test func conditionsSelectDistinctColorFamilies() {
        #expect(
            WeatherPresentation.conditionFamily(
                symbolName: "cloud.bolt.rain.fill"
            ) == .storm
        )
        #expect(
            WeatherPresentation.conditionFamily(
                symbolName: "cloud.snow.fill"
            ) == .snow
        )
        #expect(
            WeatherPresentation.conditionFamily(
                symbolName: "wind"
            ) == .wind
        )
    }
}
