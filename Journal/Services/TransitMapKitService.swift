//
//  TransitMapKitService.swift
//  Journal
//

import CoreLocation
import Foundation
import MapKit

nonisolated struct TransitMapSearchResult: Sendable, Equatable {
    let name: String
    let address: String?
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String?
    let distanceKilometers: Double?
    let walkingDurationMinutes: Double?
    let automobileDurationMinutes: Double?

    var location: Location {
        Location(
            latitude: latitude,
            longitude: longitude,
            displayName: name,
            formattedAddress: address,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}

nonisolated struct TransitRouteMetrics: Sendable, Equatable {
    let distanceMeters: Double
    let expectedTravelTime: TimeInterval
}

nonisolated enum TransitMapKitService {
    static func search(
        query: String,
        near center: CLLocationCoordinate2D,
        limit: Int = 3
    ) async throws -> [TransitMapSearchResult] {
        try await autocompleteResults(
            query: query,
            center: center,
            limit: limit
        )
    }

    @MainActor
    private static func autocompleteResults(
        query: String,
        center: CLLocationCoordinate2D,
        limit: Int
    ) async throws -> [TransitMapSearchResult] {
        let region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 50_000,
            longitudinalMeters: 50_000
        )
        let completions = try await TransitAutocompleteRequest(
            region: region
        ).completions(for: query)
        let origin = CLLocation(
            latitude: center.latitude,
            longitude: center.longitude
        )
        var results: [TransitMapSearchResult] = []

        for completion in completions.prefix(limit) {
            let request = MKLocalSearch.Request(completion: completion)
            guard let item = try await MKLocalSearch(request: request)
                .start().mapItems.first else {
                continue
            }
            let coordinate = item.location.coordinate
            let location = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )

            results.append(TransitMapSearchResult(
                name: item.name ?? query,
                address: item.address?.fullAddress,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                timeZoneIdentifier: item.timeZone?.identifier,
                distanceKilometers: origin.distance(from: location) / 1_000,
                walkingDurationMinutes: nil,
                automobileDurationMinutes: nil
            ))
        }

        return results
    }

    static func searchWithRoutes(
        query: String,
        from origin: CLLocationCoordinate2D,
        limit: Int = 3
    ) async throws -> [TransitMapSearchResult] {
        let results = try await search(query: query, near: origin, limit: limit)
        var routedResults: [TransitMapSearchResult] = []

        for result in results {
            let destination = CLLocationCoordinate2D(
                latitude: result.latitude,
                longitude: result.longitude
            )
            async let walking = travelTime(
                from: origin,
                to: destination,
                transportType: .walking
            )
            async let automobile = travelTime(
                from: origin,
                to: destination,
                transportType: .automobile
            )
            let walkingSeconds = try? await walking
            let automobileSeconds = try? await automobile

            routedResults.append(
                TransitMapSearchResult(
                    name: result.name,
                    address: result.address,
                    latitude: result.latitude,
                    longitude: result.longitude,
                    timeZoneIdentifier: result.timeZoneIdentifier,
                    distanceKilometers: result.distanceKilometers,
                    walkingDurationMinutes: walkingSeconds.map { $0 / 60 },
                    automobileDurationMinutes: automobileSeconds.map { $0 / 60 }
                )
            )
        }

        return routedResults
    }

    static func travelTime(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportType: MKDirectionsTransportType
    ) async throws -> TimeInterval {
        try await routeMetrics(
            from: origin,
            to: destination,
            transportType: transportType
        ).expectedTravelTime
    }

    static func routeMetrics(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportType: MKDirectionsTransportType,
        departureDate: Date? = nil
    ) async throws -> TransitRouteMetrics {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(
                latitude: origin.latitude,
                longitude: origin.longitude
            ),
            address: nil
        )
        request.destination = MKMapItem(
            location: CLLocation(
                latitude: destination.latitude,
                longitude: destination.longitude
            ),
            address: nil
        )
        request.transportType = transportType
        request.departureDate = departureDate

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else {
            throw TransitMapKitError.routeUnavailable
        }

        return TransitRouteMetrics(
            distanceMeters: route.distance,
            expectedTravelTime: route.expectedTravelTime
        )
    }
}

@MainActor
private final class TransitAutocompleteRequest: NSObject,
    MKLocalSearchCompleterDelegate
{
    private let completer = MKLocalSearchCompleter()
    private var continuation: CheckedContinuation<
        [MKLocalSearchCompletion],
        any Error
    >?

    init(region: MKCoordinateRegion) {
        super.init()
        completer.delegate = self
        completer.region = region
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func completions(for query: String) async throws -> [MKLocalSearchCompletion] {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            completer.queryFragment = query
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        continuation?.resume(returning: completer.results)
        continuation = nil
    }

    func completer(
        _ completer: MKLocalSearchCompleter,
        didFailWithError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

nonisolated enum TransitMapKitError: LocalizedError {
    case routeUnavailable

    var errorDescription: String? {
        "MapKit could not estimate this route."
    }
}
