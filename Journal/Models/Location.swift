//
//  Location.swift
//  Journal
//

import CoreLocation

struct Location: Hashable {
    var latitude: Double
    var longitude: Double
    var formattedAddress: String?
    var timeZoneIdentifier: String?

    init(
        latitude: Double,
        longitude: Double,
        formattedAddress: String? = nil,
        timeZoneIdentifier: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.formattedAddress = formattedAddress
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

nonisolated extension Location: Codable {}
