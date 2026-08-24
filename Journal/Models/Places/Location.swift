//
//  Location.swift
//  Journal
//

import CoreLocation

nonisolated struct Location: Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var displayName: String?
    var systemImage: PlaceSystemImage?
    var formattedAddress: String?
    var compactAddress: String?
    var timeZoneIdentifier: String?
    var cityName: String?
    var countryName: String?
    var countryCode: String?

    init(
        latitude: Double,
        longitude: Double,
        displayName: String? = nil,
        systemImage: PlaceSystemImage? = nil,
        formattedAddress: String? = nil,
        compactAddress: String? = nil,
        timeZoneIdentifier: String? = nil,
        cityName: String? = nil,
        countryName: String? = nil,
        countryCode: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.displayName = displayName
        self.systemImage = systemImage
        self.formattedAddress = formattedAddress
        self.compactAddress = compactAddress
        self.timeZoneIdentifier = timeZoneIdentifier
        self.cityName = cityName
        self.countryName = countryName
        self.countryCode = countryCode
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var preferredName: String? {
        displayName?.nilIfBlank
            ?? compactAddress?.nilIfBlank
            ?? formattedAddress?.nilIfBlank
    }

    var presentationAddress: String? {
        compactAddress?.nilIfBlank
            ?? formattedAddress?.nilIfBlank
    }

    var timelineAddress: String? {
        if let compactAddress = compactAddress?.nilIfBlank {
            let parts = addressParts(compactAddress)
            guard parts.count > 1 else { return compactAddress }
            if parts.count > 2 || !containsDigit(parts[1]) {
                return parts.dropLast().joined(separator: ", ")
            }
            return compactAddress
        }

        guard let formattedAddress = formattedAddress?.nilIfBlank else {
            return nil
        }
        let parts = addressParts(formattedAddress)
        guard let first = parts.first else { return nil }
        guard parts.count > 1, containsDigit(parts[1]) else { return first }
        return parts.prefix(2).joined(separator: ", ")
    }

    var timelineName: String? {
        displayName?.nilIfBlank ?? timelineAddress
    }

    func withFallbackDisplayName(_ name: String?) -> Location {
        guard displayName?.nilIfBlank == nil,
              let name = name?.nilIfBlank else {
            return self
        }
        var copy = self
        copy.displayName = name
        return copy
    }

    private func addressParts(_ address: String) -> [String] {
        address.split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func containsDigit(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
    }
}

nonisolated extension Location: Codable {}

nonisolated private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
