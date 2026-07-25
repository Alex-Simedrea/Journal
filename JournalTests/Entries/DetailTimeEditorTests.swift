import Foundation
import Testing

@testable import Journal

@Suite("Entry detail time editor")
struct DetailTimeEditorTests {
    @Test("Fixed duration presets retain their intended order")
    func fixedPresetOrder() {
        #expect(TimeDurationPreset.fixed.map(\.minutes) == [5, 10, 15, 30, 60])
    }

    @Test("Time zone search matches cities, regions, and identifiers")
    func timeZoneSearch() {
        #expect(
            TimeZoneCatalog.filtered(by: "bucharest")
                .contains { $0.identifier == "Europe/Bucharest" }
        )
        #expect(
            TimeZoneCatalog.filtered(by: "new york")
                .contains { $0.identifier == "America/New_York" }
        )
        #expect(
            TimeZoneCatalog.filtered(by: "america")
                .contains { $0.identifier == "America/New_York" }
        )
    }

    @Test("Known time zones are unique")
    func timeZonesAreUnique() {
        let identifiers = TimeZoneCatalog.all.map(\.identifier)
        #expect(Set(identifiers).count == identifiers.count)
    }

    @Test("GMT-style abbreviations do not repeat the GMT offset")
    func gmtDetailsAreNotDuplicated() {
        let detail = TimeZoneCatalog.detail(
            for: "Africa/Addis_Ababa",
            date: Date(timeIntervalSince1970: 1_788_000_000)
        )

        #expect(!detail.contains(" · GMT"))
    }

    @Test("MapKit durations use the model tool's tenth-minute precision")
    func mapKitDurationRounding() {
        #expect(
            TransitMapKitService.roundedTravelTime(12 * 60 + 2) == 12 * 60
        )
        #expect(
            TransitMapKitService.roundedTravelTime(12 * 60 + 4) == 12.1 * 60
        )
    }
}
