import AnyLanguageModel
import CoreLocation
import Foundation
import MapKit

nonisolated struct EstimateRouteTool: Tool {
    let recorder: TransitToolRecorder
    let routingModesByTypeOrAlias: [String: TransitRoutingMode]

    let name = "estimate_route"
    let description = """
        Estimate a trip duration between two already-resolved locations. Use exact
        locationKey values and the canonical transit type. MapKit walking time is used only
        for walking; MapKit automobile time is the rough estimate for every other transit
        type. The output duration is in minutes and includes its source. You must call this
        whenever the user explicitly gives exactly one time boundary and you need to derive
        the other timestamp, when selected-day history supplies exactly one boundary, and
        when inferring both timestamps from proximity.
        """

    func call(arguments: EstimateRouteArguments) async throws -> String {
        guard let origin = await recorder.coordinate(for: arguments.originLocationKey),
              let destination = await recorder.coordinate(
                for: arguments.destinationLocationKey
              ) else {
            return encode(
                TransitRouteEstimateOutput(
                    originLocationKey: arguments.originLocationKey,
                    destinationLocationKey: arguments.destinationLocationKey,
                    durationMinutes: nil,
                    durationSource: nil,
                    error: "Both keys must match available locationKey values"
                )
            )
        }
        guard arguments.originLocationKey != arguments.destinationLocationKey else {
            return encode(
                TransitRouteEstimateOutput(
                    originLocationKey: arguments.originLocationKey,
                    destinationLocationKey: arguments.destinationLocationKey,
                    durationMinutes: nil,
                    durationSource: nil,
                    error: "Origin and destination must be different locations"
                )
            )
        }

        let normalizedType = TransitToolQueryValidator.normalize(arguments.transitType)
        let routingMode = routingModesByTypeOrAlias[normalizedType] ?? .automobile
        let transportType: MKDirectionsTransportType = routingMode == .walking
            ? .walking
            : .automobile

        do {
            let duration = try await TransitMapKitService.travelTime(
                from: CLLocationCoordinate2D(
                    latitude: origin.latitude,
                    longitude: origin.longitude
                ),
                to: CLLocationCoordinate2D(
                    latitude: destination.latitude,
                    longitude: destination.longitude
                ),
                transportType: transportType
            )
            return encode(
                TransitRouteEstimateOutput(
                    originLocationKey: arguments.originLocationKey,
                    destinationLocationKey: arguments.destinationLocationKey,
                    durationMinutes: rounded(duration / 60),
                    durationSource: routingMode == .walking
                        ? "mapkitWalking"
                        : "mapkitCarFallback",
                    error: nil
                )
            )
        } catch {
            return encode(
                TransitRouteEstimateOutput(
                    originLocationKey: arguments.originLocationKey,
                    destinationLocationKey: arguments.destinationLocationKey,
                    durationMinutes: nil,
                    durationSource: nil,
                    error: "No route duration could be estimated"
                )
            )
        }
    }

    private func encode(_ output: TransitRouteEstimateOutput) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(output),
              let value = String(data: data, encoding: .utf8) else {
            return #"{"error":"Could not encode route estimate"}"#
        }
        return value
    }

    private func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

nonisolated struct CompareRoutesTool: Tool {
    let recorder: TransitToolRecorder
    let routingModesByTypeOrAlias: [String: TransitRoutingMode]

    let name = "compare_routes"
    let description = """
        Compare multiple locations that plausibly match one endpoint when the opposite
        endpoint is already resolved. This is the required tool for ambiguity such as two
        saved places containing the same short name or an exact alias that conflicts with
        the trip's geography. It returns straight-line distance and the relevant MapKit
        duration for every candidate. Use walking for Walk and automobile for all other
        transit types. Do not use current-location distance as a substitute for this tool.
        """

    func call(arguments: CompareRoutesArguments) async throws -> String {
        guard arguments.candidateEndpoint != .visit else {
            return encode(
                SavedRouteComparisonOutput(
                    candidateEndpoint: arguments.candidateEndpoint.label,
                    fixedLocationKey: arguments.fixedLocationKey,
                    error: "Route comparison is available only for transit endpoints",
                    candidates: []
                )
            )
        }
        guard let fixed = await recorder.coordinate(
            for: arguments.fixedLocationKey
        ) else {
            return encode(
                SavedRouteComparisonOutput(
                    candidateEndpoint: arguments.candidateEndpoint.label,
                    fixedLocationKey: arguments.fixedLocationKey,
                    error: "fixedLocationKey must match an available location key",
                    candidates: []
                )
            )
        }

        let normalizedType = TransitToolQueryValidator.normalize(arguments.transitType)
        let routingMode = routingModesByTypeOrAlias[normalizedType] ?? .automobile
        let transportType: MKDirectionsTransportType = routingMode == .walking
            ? .walking
            : .automobile
        let durationSource = routingMode == .walking
            ? "mapkitWalking"
            : "mapkitCarFallback"
        var seen: Set<String> = []
        var comparisons: [SavedRouteCandidateOutput] = []

        for candidateKey in arguments.candidateLocationKeys where seen.insert(candidateKey).inserted {
            guard let candidate = await recorder.coordinate(for: candidateKey) else {
                comparisons.append(
                    SavedRouteCandidateOutput(
                        candidateLocationKey: candidateKey,
                        originLocationKey: nil,
                        destinationLocationKey: nil,
                        straightLineDistanceKilometers: nil,
                        durationMinutes: nil,
                        durationSource: nil,
                        error: "candidateLocationKey is not an available location key"
                    )
                )
                continue
            }

            let origin: TransitToolCoordinate
            let destination: TransitToolCoordinate
            let originKey: String
            let destinationKey: String
            switch arguments.candidateEndpoint {
            case .origin:
                origin = candidate
                originKey = candidateKey
                destination = fixed
                destinationKey = arguments.fixedLocationKey
            case .destination:
                origin = fixed
                originKey = arguments.fixedLocationKey
                destination = candidate
                destinationKey = candidateKey
            case .visit:
                continue
            }

            let distance = CLLocation(
                latitude: origin.latitude,
                longitude: origin.longitude
            ).distance(
                from: CLLocation(
                    latitude: destination.latitude,
                    longitude: destination.longitude
                )
            ) / 1_000

            do {
                let duration = try await TransitMapKitService.travelTime(
                    from: CLLocationCoordinate2D(
                        latitude: origin.latitude,
                        longitude: origin.longitude
                    ),
                    to: CLLocationCoordinate2D(
                        latitude: destination.latitude,
                        longitude: destination.longitude
                    ),
                    transportType: transportType
                )
                comparisons.append(
                    SavedRouteCandidateOutput(
                        candidateLocationKey: candidateKey,
                        originLocationKey: originKey,
                        destinationLocationKey: destinationKey,
                        straightLineDistanceKilometers: rounded(distance),
                        durationMinutes: rounded(duration / 60),
                        durationSource: durationSource,
                        error: nil
                    )
                )
            } catch {
                comparisons.append(
                    SavedRouteCandidateOutput(
                        candidateLocationKey: candidateKey,
                        originLocationKey: originKey,
                        destinationLocationKey: destinationKey,
                        straightLineDistanceKilometers: rounded(distance),
                        durationMinutes: nil,
                        durationSource: durationSource,
                        error: "MapKit could not calculate this route"
                    )
                )
            }
        }

        return encode(
            SavedRouteComparisonOutput(
                candidateEndpoint: arguments.candidateEndpoint.label,
                fixedLocationKey: arguments.fixedLocationKey,
                error: comparisons.isEmpty ? "No candidate keys were provided" : nil,
                candidates: comparisons
            )
        )
    }

    private func encode(_ output: SavedRouteComparisonOutput) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(output),
              let value = String(data: data, encoding: .utf8) else {
            return #"{"error":"Could not encode route comparisons"}"#
        }
        return value
    }

    private func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

nonisolated private struct SavedRouteComparisonOutput: Encodable {
    let candidateEndpoint: String
    let fixedLocationKey: String
    let error: String?
    let candidates: [SavedRouteCandidateOutput]
}

nonisolated private struct SavedRouteCandidateOutput: Encodable {
    let candidateLocationKey: String
    let originLocationKey: String?
    let destinationLocationKey: String?
    let straightLineDistanceKilometers: Double?
    let durationMinutes: Double?
    let durationSource: String?
    let error: String?
}

nonisolated private struct TransitRouteEstimateOutput: Encodable {
    let originLocationKey: String
    let destinationLocationKey: String
    let durationMinutes: Double?
    let durationSource: String?
    let error: String?
}
