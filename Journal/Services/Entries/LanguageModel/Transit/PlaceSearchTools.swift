import AnyLanguageModel
import CoreLocation
import Foundation
import MapKit

nonisolated struct SearchPlacesTool: Tool {
    let latitude: Double
    let longitude: Double
    let prohibitedQueries: Set<String>
    let recorder: TransitToolRecorder

    let name = "search_places"
    let description = """
        Search MapKit near the user's current location for exactly one origin, destination,
        or visited place that did not match SAVED PLACES or LOCATION HISTORY. The query must
        contain only that place's words from the user text. Never search for a transit type,
        service, person,
        time phrase, or a location already resolved from the supplied context.
        """

    func call(arguments: SearchPlacesArguments) async throws -> String {
        guard !prohibitedQueries.contains(
            TransitToolQueryValidator.normalize(arguments.query)
        ) else {
            return TransitToolOutputFormatter.error(
                role: arguments.role,
                query: arguments.query,
                message: "The query is a transit type or alias, not a place endpoint"
            )
        }

        let results = try await TransitMapKitService.search(
            query: arguments.query,
            near: CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            )
        )
        let search = await recorder.record(
            role: arguments.role,
            query: arguments.query,
            results: results
        )
        return TransitToolOutputFormatter.string(search)
    }
}

nonisolated struct SearchDestinationWithRoutesTool: Tool {
    let prohibitedQueries: Set<String>
    let recorder: TransitToolRecorder

    let name = "search_destination_with_routes"
    let description = """
        Search MapKit for an unresolved destination when the origin is already a resolved
        location. Pass the exact origin locationKey and only the destination words from the
        user text. Results include distance from the origin plus walking and automobile time.
        Never pass a name in place of a key and never search for the transit type.
        """

    func call(arguments: SearchDestinationWithRoutesArguments) async throws -> String {
        guard !prohibitedQueries.contains(
            TransitToolQueryValidator.normalize(arguments.query)
        ) else {
            return TransitToolOutputFormatter.error(
                role: .destination,
                query: arguments.query,
                message: "The query is a transit type or alias, not a destination"
            )
        }

        guard let origin = await recorder.coordinate(
            for: arguments.originLocationKey
        ) else {
            return TransitToolOutputFormatter.error(
                role: .destination,
                query: arguments.query,
                message: "originLocationKey is not an available location key"
            )
        }

        let results = try await TransitMapKitService.searchWithRoutes(
            query: arguments.query,
            from: CLLocationCoordinate2D(
                latitude: origin.latitude,
                longitude: origin.longitude
            )
        )
        let search = await recorder.record(
            role: .destination,
            query: arguments.query,
            results: results
        )
        return TransitToolOutputFormatter.string(search)
    }
}
