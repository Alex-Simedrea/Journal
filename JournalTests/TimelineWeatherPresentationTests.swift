import Foundation
import Testing
@testable import Journal

struct TimelineWeatherPresentationTests {
    @Test func solarPhaseUsesCoordinateAndHistoricalDate() throws {
        let noon = try Date("2026-03-20T12:00:00Z", strategy: .iso8601)
        let midnight = try Date("2026-03-20T00:00:00Z", strategy: .iso8601)

        #expect(
            TimelineWeatherPresentation.skyPhase(
                date: noon,
                latitude: 0,
                longitude: 0,
                symbolName: "sun.max.fill",
                timeZone: .gmt
            ) == .day
        )
        #expect(
            TimelineWeatherPresentation.skyPhase(
                date: midnight,
                latitude: 0,
                longitude: 0,
                symbolName: "sun.max.fill",
                timeZone: .gmt
            ) == .night
        )
    }

    @Test func dawnAndDuskHaveDedicatedPalettes() {
        let dawn = TimelineWeatherPresentation.gradientHexes(
            symbolName: "sun.max.fill",
            phase: .dawn
        )
        let day = TimelineWeatherPresentation.gradientHexes(
            symbolName: "sun.max.fill",
            phase: .day
        )
        let dusk = TimelineWeatherPresentation.gradientHexes(
            symbolName: "sun.max.fill",
            phase: .dusk
        )
        let night = TimelineWeatherPresentation.gradientHexes(
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
            TimelineWeatherPresentation.conditionFamily(
                symbolName: "cloud.bolt.rain.fill"
            ) == .storm
        )
        #expect(
            TimelineWeatherPresentation.conditionFamily(
                symbolName: "cloud.snow.fill"
            ) == .snow
        )
        #expect(
            TimelineWeatherPresentation.conditionFamily(
                symbolName: "wind"
            ) == .wind
        )
    }
}
