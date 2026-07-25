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
}
