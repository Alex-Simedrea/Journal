import Foundation
import MapKit

@MainActor
enum AirportLocationResolver {
    static func resolve(
        iataCode: String,
        cityName: String
    ) async -> Location? {
        let code = normalizedCode(iataCode)
        guard code.count == 3,
              code.allSatisfy(\.isLetter) else { return nil }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(code) \(cityName) airport"
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(
            including: [.airport, .airportTerminal]
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let airport = bestAirport(
                in: response.mapItems,
                code: code,
                cityName: cityName
            ) else { return nil }
            return LocationService.location(
                for: airport,
                fallbackName: "\(cityName) Airport"
            )
        } catch {
            return nil
        }
    }

    private static func bestAirport(
        in items: [MKMapItem],
        code: String,
        cityName: String
    ) -> MKMapItem? {
        items.enumerated()
            .filter { _, item in
                item.pointOfInterestCategory == .airport
                    || item.pointOfInterestCategory == .airportTerminal
            }
            .max { lhs, rhs in
                score(
                    lhs.element,
                    resultIndex: lhs.offset,
                    code: code,
                    cityName: cityName
                ) < score(
                    rhs.element,
                    resultIndex: rhs.offset,
                    code: code,
                    cityName: cityName
                )
            }?
            .element
    }

    private static func score(
        _ item: MKMapItem,
        resultIndex: Int,
        code: String,
        cityName: String
    ) -> Int {
        let searchableText = [
            item.name,
            item.address?.fullAddress,
            item.addressRepresentations?.cityName,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        let words = Set(
            searchableText.uppercased().split {
                !$0.isLetter && !$0.isNumber
            }.map(String.init)
        )
        let normalizedCity = normalize(cityName)
        let normalizedResult = normalize(searchableText)

        var result = max(0, 20 - resultIndex)
        if words.contains(code) { result += 200 }
        if !normalizedCity.isEmpty,
           normalizedResult.contains(normalizedCity) {
            result += 60
        }
        if item.pointOfInterestCategory == .airport {
            result += 40
        }
        return result
    }

    private static func normalizedCode(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
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
