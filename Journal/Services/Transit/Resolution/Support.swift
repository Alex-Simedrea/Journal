import CoreLocation
import Foundation

extension TransitResolutionService {
    static func durationSource(
        for source: GeneratedDurationSource
    ) -> DurationSource {
        switch source {
        case .none: .unresolved
        case .mapkitWalking: .mapkitWalking
        case .mapkitCarFallback: .mapkitCarFallback
        }
    }

    static func candidates(
        keys: [String],
        endpoint: GeneratedPlaceRole,
        references: EntryPromptReferences,
        searches: [TransitToolSearch]
    ) -> [LocationCandidate] {
        let searchResults = Dictionary(
            uniqueKeysWithValues: searches
                .filter { $0.role == endpoint }
                .flatMap(\.candidates)
                .map { ($0.candidateKey, $0.result) }
        )
        var seen: Set<String> = []

        return keys.compactMap { key in
            guard seen.insert(key).inserted else { return nil }
            if let reference = references.locationsByKey[key] {
                return LocationCandidate(
                    name: reference.displayName,
                    address: reference.location.formattedAddress,
                    latitude: reference.location.latitude,
                    longitude: reference.location.longitude,
                    timeZoneIdentifier: reference.location.timeZoneIdentifier
                )
            }
            guard let result = searchResults[key] else { return nil }
            return LocationCandidate(
                name: result.name,
                address: result.address,
                latitude: result.latitude,
                longitude: result.longitude,
                timeZoneIdentifier: result.timeZoneIdentifier,
                distanceKilometers: result.distanceKilometers,
                walkingDurationMinutes: result.walkingDurationMinutes,
                automobileDurationMinutes: result.automobileDurationMinutes
            )
        }
    }

    static func searchResult(
        key: String,
        endpoint: GeneratedPlaceRole,
        searches: [TransitToolSearch]
    ) -> TransitMapSearchResult? {
        searches
            .filter { $0.role == endpoint }
            .flatMap(\.candidates)
            .first { $0.candidateKey == key }?
            .result
    }

    static func parsedDate(_ value: String?) -> Date? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return try? Date(value, strategy: .iso8601)
    }

    static func isNear(
        _ currentLocation: Location,
        location: Location
    ) -> Bool {
        let distance = CLLocation(
            latitude: currentLocation.latitude,
            longitude: currentLocation.longitude
        ).distance(
            from: CLLocation(
                latitude: location.latitude,
                longitude: location.longitude
            )
        )
        return distance <= 200
    }

    static func sameLocation(
        _ lhs: Location?,
        _ rhs: Location
    ) -> Bool {
        guard let lhs else { return false }
        return CLLocation(
            latitude: lhs.latitude,
            longitude: lhs.longitude
        ).distance(
            from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        ) <= 100
    }

    static func reviewReason(
        _ review: GeneratedFieldReview,
        fallback: String
    ) -> String {
        guard let reason = review.reason?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !reason.isEmpty else {
            return fallback
        }
        return reason
    }

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .lowercased()
    }
}

struct LocationResolution {
    let place: Place?
    let location: Location?
    let candidates: [LocationCandidate]
    let validationError: String?
}

struct PeopleResolution {
    let people: [Person]
    let unresolved: [String]
    let reviewReason: String?
}

struct TimeResolution {
    let start: Date?
    let end: Date?
    let confidence: TimeConfidence
    let durationSource: DurationSource
    let error: String?
}
