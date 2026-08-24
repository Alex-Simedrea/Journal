import Foundation
import MapKit
import Testing

@testable import Journal

@Suite("Place system image inference")
struct PlaceSystemImageTests {
    @Test("MapKit food and retail categories use matching place symbols")
    func foodAndRetailCategories() {
        #expect(
            PlaceSystemImage(pointOfInterestCategory: .restaurant) == .dining
        )
        #expect(
            PlaceSystemImage(pointOfInterestCategory: .cafe) == .cafe
        )
        #expect(
            PlaceSystemImage(pointOfInterestCategory: .foodMarket) == .cart
        )
        #expect(
            PlaceSystemImage(pointOfInterestCategory: .store) == .storefront
        )
    }

    @Test("MapKit travel and outdoor categories use matching place symbols")
    func travelAndOutdoorCategories() {
        #expect(
            PlaceSystemImage(pointOfInterestCategory: .airport) == .airport
        )
        #expect(
            PlaceSystemImage(pointOfInterestCategory: .publicTransport) == .tram
        )
        #expect(
            PlaceSystemImage(pointOfInterestCategory: .beach) == .beach
        )
        #expect(
            PlaceSystemImage(pointOfInterestCategory: .nationalPark) == .park
        )
    }

    @Test("MapKit health, culture, and activity categories are inferred")
    func healthCultureAndActivityCategories() {
        #expect(
            PlaceSystemImage(pointOfInterestCategory: .hospital) == .medical
        )
        #expect(
            PlaceSystemImage(pointOfInterestCategory: .pharmacy) == .pharmacy
        )
        #expect(
            PlaceSystemImage(pointOfInterestCategory: .movieTheater) == .theater
        )
        #expect(
            PlaceSystemImage(pointOfInterestCategory: .fitnessCenter) == .gym
        )
        #expect(
            PlaceSystemImage(pointOfInterestCategory: .soccer) == .soccer
        )
    }

    @Test("Missing or unsupported MapKit categories preserve the current symbol")
    func missingCategory() {
        #expect(
            PlaceSystemImage(pointOfInterestCategory: nil) == nil
        )
        #expect(
            PlaceSystemImage(pointOfInterestCategory: .restroom) == nil
        )
    }

    @Test("MapKit locations retain landmark names, addresses, and symbols")
    func mapKitLocationMetadata() throws {
        let result = TransitMapSearchResult(
            name: "Reyna Beach",
            address: "Strada Pescarilor 1, Constanța",
            latitude: 44.21,
            longitude: 28.65,
            timeZoneIdentifier: "Europe/Bucharest",
            pointOfInterestCategory: .beach,
            distanceKilometers: 2.4,
            walkingDurationMinutes: nil,
            automobileDurationMinutes: nil
        )

        let location = result.location
        #expect(location.preferredName == "Reyna Beach")
        #expect(
            location.presentationAddress
                == "Strada Pescarilor 1, Constanța"
        )
        #expect(location.systemImage == .beach)

        let data = try JSONEncoder().encode(location)
        let restored = try JSONDecoder().decode(Location.self, from: data)
        #expect(restored.displayName == "Reyna Beach")
        #expect(restored.systemImage == .beach)
    }

    @Test("Historical locations decode without landmark symbols")
    func historicalLocationCompatibility() throws {
        let data = try #require(
            """
            {
              "latitude": 44.21,
              "longitude": 28.65,
              "displayName": "Reyna Beach",
              "formattedAddress": "Strada Pescarilor 1, Constanța"
            }
            """.data(using: .utf8)
        )

        let location = try JSONDecoder().decode(Location.self, from: data)
        #expect(location.preferredName == "Reyna Beach")
        #expect(location.systemImage == nil)
    }
}
