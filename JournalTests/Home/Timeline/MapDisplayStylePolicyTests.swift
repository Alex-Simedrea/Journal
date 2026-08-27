import CoreLocation
import Testing

@testable import Journal

struct MapDisplayStylePolicyTests {
    @Test("Nearby and single-marker maps remain standard")
    func nearbyMarkers() {
        #expect(
            !JournalMapDisplayStylePolicy.usesHybridStyle(
                for: [
                    CLLocationCoordinate2D(latitude: 44.43, longitude: 26.10),
                    CLLocationCoordinate2D(latitude: 48.86, longitude: 2.35),
                ]
            )
        )
        #expect(
            !JournalMapDisplayStylePolicy.usesHybridStyle(
                for: [
                    CLLocationCoordinate2D(latitude: 44.43, longitude: 26.10),
                ]
            )
        )
    }

    @Test("Any pair over three thousand kilometers selects hybrid")
    func distantMarkers() {
        #expect(
            JournalMapDisplayStylePolicy.usesHybridStyle(
                for: [
                    CLLocationCoordinate2D(latitude: 44.43, longitude: 26.10),
                    CLLocationCoordinate2D(latitude: 48.86, longitude: 2.35),
                    CLLocationCoordinate2D(latitude: 40.71, longitude: -74.01),
                ]
            )
        )
    }
}
