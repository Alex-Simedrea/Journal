import AnyLanguageModel
import CoreLocation
import Foundation
import MapKit

@Generable(description: "Arguments for a nearby MapKit endpoint search")
nonisolated struct SearchPlacesArguments {
    @Guide(description: "Whether this search is for the origin, destination, or visited place")
    let role: GeneratedPlaceRole
    @Guide(description: "Only the unresolved place wording copied from the user text")
    let query: String
}

@Generable(description: "Arguments for a destination search with route estimates from any resolved origin")
nonisolated struct SearchDestinationWithRoutesArguments {
    @Guide(description: "Only the unresolved destination wording copied from the user text")
    let query: String
    @Guide(description: "The exact locationKey for the resolved origin")
    let originLocationKey: String
}

@Generable(description: "Arguments for estimating the duration between two resolved locations")
nonisolated struct EstimateRouteArguments {
    @Guide(description: "The exact locationKey for the resolved origin")
    let originLocationKey: String
    @Guide(description: "The exact locationKey for the resolved destination")
    let destinationLocationKey: String
    @Guide(description: "The exact canonicalName from TRANSIT TYPES")
    let transitType: String
}

@Generable(description: "Arguments for comparing several endpoint matches by route")
nonisolated struct CompareRoutesArguments {
    @Guide(description: "Whether candidateLocationKeys are possible origins or destinations")
    let candidateEndpoint: GeneratedPlaceRole
    @Guide(description: "The exact locationKey for the already-resolved opposite endpoint")
    let fixedLocationKey: String
    @Guide(description: "All plausible location keys for the ambiguous endpoint", .maximumCount(4))
    let candidateLocationKeys: [String]
    @Guide(description: "The exact canonicalName from TRANSIT TYPES")
    let transitType: String
}

nonisolated struct TransitToolCoordinate: Sendable {
    let latitude: Double
    let longitude: Double
}

nonisolated struct TransitToolCandidate: Sendable {
    let candidateKey: String
    let result: TransitMapSearchResult
}

nonisolated struct TransitToolSearch: Sendable {
    let role: GeneratedPlaceRole
    let query: String
    let candidates: [TransitToolCandidate]
}

actor TransitToolRecorder {
    private var searches: [TransitToolSearch] = []
    private var coordinatesByKey: [String: TransitToolCoordinate]

    init(coordinatesByKey: [String: TransitToolCoordinate] = [:]) {
        self.coordinatesByKey = coordinatesByKey
    }

    func record(
        role: GeneratedPlaceRole,
        query: String,
        results: [TransitMapSearchResult]
    ) -> TransitToolSearch {
        let searchNumber = searches.count + 1
        let candidates = results.enumerated().map { index, result in
            TransitToolCandidate(
                candidateKey: "\(role.label)-search-\(searchNumber)-candidate-\(index + 1)",
                result: result
            )
        }
        let search = TransitToolSearch(
            role: role,
            query: query,
            candidates: candidates
        )
        for candidate in candidates {
            coordinatesByKey[candidate.candidateKey] = TransitToolCoordinate(
                latitude: candidate.result.latitude,
                longitude: candidate.result.longitude
            )
        }
        searches.append(search)
        return search
    }

    func coordinate(for key: String) -> TransitToolCoordinate? {
        coordinatesByKey[key]
    }

    func recordedSearches() -> [TransitToolSearch] {
        searches
    }
}
