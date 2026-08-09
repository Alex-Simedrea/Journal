import Foundation
import SwiftData

@MainActor
enum AirportPlaceStore {
    static func attachAirports(
        to entry: LogEntry,
        originCode: String?,
        originCityName: String,
        destinationCode: String?,
        destinationCityName: String,
        in modelContext: ModelContext
    ) throws {
        guard let details = entry.transitDetails,
              normalize(details.type) == normalize("Flight") else {
            return
        }

        var places = try modelContext.fetch(FetchDescriptor<Place>())

        if let place = attachAirport(
            code: originCode,
            cityName: originCityName,
            location: details.originLocation,
            selectedPlace: details.originPlace,
            places: &places,
            in: modelContext
        ) {
            details.originPlace = place
            details.originLocation = place.location
        }

        if let place = attachAirport(
            code: destinationCode,
            cityName: destinationCityName,
            location: details.destinationLocation,
            selectedPlace: details.destinationPlace,
            places: &places,
            in: modelContext
        ) {
            details.destinationPlace = place
            details.destinationLocation = place.location
        }
    }

    private static func attachAirport(
        code: String?,
        cityName: String,
        location: Location?,
        selectedPlace: Place?,
        places: inout [Place],
        in modelContext: ModelContext
    ) -> Place? {
        guard let code = normalizedAirportCode(code) else {
            return selectedPlace
        }

        if let selectedPlace {
            addAliases(
                to: selectedPlace,
                code: code,
                cityName: cityName,
                location: selectedPlace.location
            )
            return selectedPlace
        }

        if let existing = airport(matching: code, in: places) {
            addAliases(
                to: existing,
                code: code,
                cityName: cityName,
                location: existing.location
            )
            return existing
        }

        guard let location else { return nil }
        let airport = Place(
            name: airportName(
                location: location,
                cityName: cityName,
                code: code
            ),
            location: location,
            systemImage: .airport
        )
        addAliases(
            to: airport,
            code: code,
            cityName: cityName,
            location: location
        )
        modelContext.insert(airport)
        places.append(airport)
        return airport
    }

    private static func airport(
        matching code: String,
        in places: [Place]
    ) -> Place? {
        let normalizedCode = normalize(code)
        let matches = places.filter { place in
            normalize(place.name) == normalizedCode
                || place.aliases.contains {
                    normalize($0) == normalizedCode
                }
        }
        if matches.count == 1 {
            return matches[0]
        }
        let airportMatches = matches.filter { $0.systemImage == .airport }
        return airportMatches.count == 1 ? airportMatches[0] : nil
    }

    private static func addAliases(
        to place: Place,
        code: String,
        cityName: String,
        location: Location
    ) {
        let city = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        let locationCity = location.cityName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            code,
            city,
            locationCity,
            city.isEmpty ? nil : "\(city) (\(code))",
        ].compactMap { $0 }

        var known = Set(
            ([place.name] + place.aliases).map(normalize)
        )
        for candidate in candidates where !candidate.isEmpty {
            if known.insert(normalize(candidate)).inserted {
                place.aliases.append(candidate)
            }
        }
    }

    private static func airportName(
        location: Location,
        cityName: String,
        code: String
    ) -> String {
        if let displayName = location.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            return displayName
        }
        let city = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        return city.isEmpty ? code : "\(city) Airport"
    }

    private static func normalizedAirportCode(_ code: String?) -> String? {
        guard let code = code?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
              !code.isEmpty else {
            return nil
        }
        return code
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
