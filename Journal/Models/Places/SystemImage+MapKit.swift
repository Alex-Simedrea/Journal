import MapKit

extension PlaceSystemImage {
    init?(
        pointOfInterestCategory category: MKPointOfInterestCategory?
    ) {
        guard let category else { return nil }

        switch category {
        case .airport, .airportTerminal:
            self = .airport
        case .amusementPark, .fairground, .ticketOffice:
            self = .ticket
        case .animalService, .zoo:
            self = .pets
        case .aquarium, .fishing, .kayaking, .surfing, .swimming:
            self = .water
        case .atm, .bank, .castle, .conventionCenter, .fireStation,
             .fortress, .nationalMonument, .police, .postOffice:
            self = .civicBuilding
        case .automotiveDealership, .automotiveRepair, .carRental,
             .commercialVehicleDealership, .goKart, .motorbikeDealership:
            self = .car
        case .bakery:
            self = .cake
        case .baseball, .bowling, .golf, .miniGolf, .skatePark, .skating,
             .stadium, .tennis, .volleyball:
            self = .sports
        case .basketball:
            self = .basketball
        case .beach:
            self = .beach
        case .beauty, .laundry, .store:
            self = .storefront
        case .brewery, .distillery, .nightlife, .winery:
            self = .bar
        case .cafe:
            self = .cafe
        case .campground, .rvPark:
            self = .camping
        case .evCharger, .gasStation:
            self = .gasStation
        case .fitnessCenter:
            self = .gym
        case .foodMarket:
            self = .cart
        case .hiking:
            self = .walking
        case .hospital:
            self = .medical
        case .hotel:
            self = .hotel
        case .informationBooth, .visitorCenter:
            self = .people
        case .landmark, .museum, .scenicView:
            self = .camera
        case .library:
            self = .library
        case .marina:
            self = .ferry
        case .movieTheater, .theater:
            self = .theater
        case .musicVenue:
            self = .music
        case .nationalPark, .park, .picnicArea, .rangerStation:
            self = .park
        case .parking:
            self = .parking
        case .pharmacy:
            self = .pharmacy
        case .planetarium:
            self = .star
        case .publicTransport:
            self = .tram
        case .restaurant:
            self = .dining
        case .restArea:
            self = .car
        case .rockClimbing, .skiing:
            self = .mountain
        case .school, .university:
            self = .school
        case .soccer:
            self = .soccer
        case .spa:
            self = .heart
        default:
            return nil
        }
    }
}
