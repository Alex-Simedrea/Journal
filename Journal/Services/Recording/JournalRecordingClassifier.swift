import CoreLocation
import Foundation

nonisolated struct JournalRecordingClassificationConfiguration: Sendable {
    var maximumHorizontalAccuracy = 120.0
    var visitRadiusMeters = 80.0
    var visitCoverageFraction = 0.9
    var visitMaximumEndpointDisplacementMeters = 140.0
    var minimumTransitDistanceMeters = 250.0
    var endpointFraction = 0.2
    var maximumEndpointSampleCount = 6
    var polylineToleranceMeters = 25.0
    var minimumMotionConfidenceRawValue = 1
}

nonisolated enum JournalRecordingClassification: Sendable, Equatable {
    case visit(
        coordinate: RecordedRoutePoint,
        radiusMeters: Double
    )
    case transit(
        origin: RecordedRoutePoint,
        destination: RecordedRoutePoint,
        route: [RecordedRoutePoint],
        distanceMeters: Double,
        mode: RecordedTransitMode
    )
}

nonisolated enum JournalRecordingClassifier {
    static func classify(
        points: [TrackedLocationPoint],
        motion: [RecordedMotionObservation],
        configuration: JournalRecordingClassificationConfiguration = .init()
    ) -> JournalRecordingClassification? {
        let reliable = points
            .filter { point in
                point.latitude.isFinite
                    && point.longitude.isFinite
                    && (-90...90).contains(point.latitude)
                    && (-180...180).contains(point.longitude)
                    && point.horizontalAccuracy >= 0
                    && point.horizontalAccuracy
                        <= configuration.maximumHorizontalAccuracy
            }
            .sorted { $0.timestamp < $1.timestamp }
        guard let first = reliable.first else { return nil }

        let center = medianPoint(reliable)
        let radii = reliable.map { distance($0, center) }.sorted()
        let coverageIndex = min(
            radii.count - 1,
            max(
                0,
                Int(ceil(Double(radii.count) * configuration.visitCoverageFraction)) - 1
            )
        )
        let coverageRadius = radii[coverageIndex]
        let endpointDisplacement = reliable.last.map { distance(first, $0) } ?? 0
        let traveledDistance = routeDistance(reliable)

        let geographicallyClustered = coverageRadius
            <= configuration.visitRadiusMeters
            && endpointDisplacement
                <= configuration.visitMaximumEndpointDisplacementMeters
        let movementIsTooSmallForTransit = traveledDistance
            < configuration.minimumTransitDistanceMeters
            && endpointDisplacement
                <= configuration.visitMaximumEndpointDisplacementMeters
        if geographicallyClustered || movementIsTooSmallForTransit {
            return .visit(
                coordinate: RecordedRoutePoint(
                    latitude: center.latitude,
                    longitude: center.longitude,
                    timestamp: center.timestamp
                ),
                radiusMeters: coverageRadius
            )
        }

        let endpointCount = min(
            configuration.maximumEndpointSampleCount,
            max(1, Int(ceil(Double(reliable.count) * configuration.endpointFraction)))
        )
        let origin = representativePoint(Array(reliable.prefix(endpointCount)))
        let destination = representativePoint(Array(reliable.suffix(endpointCount)))
        let route = simplify(
            reliable.map {
                RecordedRoutePoint(
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    timestamp: $0.timestamp
                )
            },
            toleranceMeters: configuration.polylineToleranceMeters
        )
        return .transit(
            origin: origin,
            destination: destination,
            route: route,
            distanceMeters: traveledDistance,
            mode: dominantMode(
                motion: motion,
                points: reliable,
                minimumMotionConfidenceRawValue:
                    configuration.minimumMotionConfidenceRawValue
            )
        )
    }

    static func dominantMode(
        motion: [RecordedMotionObservation],
        points: [TrackedLocationPoint],
        minimumMotionConfidenceRawValue: Int = 1
    ) -> RecordedTransitMode {
        var durations: [RecordedTransitMode: TimeInterval] = [:]
        for observation in motion
        where observation.confidenceRawValue >= minimumMotionConfidenceRawValue {
            let duration = max(
                0,
                observation.endTime.timeIntervalSince(observation.startTime)
            )
            let mode: RecordedTransitMode? = switch observation.kind {
            case .walking, .running: .walking
            case .cycling: .cycling
            case .automotive: .automotive
            case .stationary, .unknown: nil
            }
            if let mode {
                durations[mode, default: 0] += duration
            }
        }
        if let dominant = durations.max(by: { $0.value < $1.value }),
           dominant.value > 0 {
            return dominant.key
        }

        let speeds = points.compactMap(\.speed).filter { $0 >= 0 && $0 < 80 }
        guard !speeds.isEmpty else { return .unknown }
        let medianSpeed = speeds.sorted()[speeds.count / 2]
        if medianSpeed <= 2.7 { return .walking }
        if medianSpeed <= 10 { return .cycling }
        // High speed alone is deliberately not treated as automotive.
        return .unknown
    }

    static func routeDistance(_ points: [TrackedLocationPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { result, pair in
            let separation = distance(pair.0, pair.1)
            let noiseFloor = min(
                25,
                max(pair.0.horizontalAccuracy, pair.1.horizontalAccuracy) * 0.25
            )
            return result + (separation >= noiseFloor ? separation : 0)
        }
    }

    private static func medianPoint(
        _ points: [TrackedLocationPoint]
    ) -> TrackedLocationPoint {
        let latitudes = points.map(\.latitude).sorted()
        let longitudes = points.map(\.longitude).sorted()
        let middle = points.count / 2
        return TrackedLocationPoint(
            latitude: latitudes[middle],
            longitude: longitudes[middle],
            timestamp: points[middle].timestamp,
            horizontalAccuracy: points.map(\.horizontalAccuracy).sorted()[middle],
            altitude: nil,
            speed: nil,
            course: nil
        )
    }

    private static func representativePoint(
        _ points: [TrackedLocationPoint]
    ) -> RecordedRoutePoint {
        let weighted = points.reduce(into: (latitude: 0.0, longitude: 0.0, weight: 0.0)) {
            result, point in
            let weight = 1 / max(5, point.horizontalAccuracy)
            result.latitude += point.latitude * weight
            result.longitude += point.longitude * weight
            result.weight += weight
        }
        let timestamp = points[points.count / 2].timestamp
        return RecordedRoutePoint(
            latitude: weighted.latitude / weighted.weight,
            longitude: weighted.longitude / weighted.weight,
            timestamp: timestamp
        )
    }

    private static func simplify(
        _ points: [RecordedRoutePoint],
        toleranceMeters: Double
    ) -> [RecordedRoutePoint] {
        guard points.count > 2 else { return points }
        var greatestDistance = 0.0
        var greatestIndex = 0
        for index in 1..<(points.count - 1) {
            let distance = perpendicularDistance(
                points[index],
                lineStart: points[0],
                lineEnd: points[points.count - 1]
            )
            if distance > greatestDistance {
                greatestDistance = distance
                greatestIndex = index
            }
        }
        guard greatestDistance > toleranceMeters else {
            return [points[0], points[points.count - 1]]
        }
        let first = simplify(
            Array(points[...greatestIndex]),
            toleranceMeters: toleranceMeters
        )
        let second = simplify(
            Array(points[greatestIndex...]),
            toleranceMeters: toleranceMeters
        )
        return first.dropLast() + second
    }

    private static func perpendicularDistance(
        _ point: RecordedRoutePoint,
        lineStart: RecordedRoutePoint,
        lineEnd: RecordedRoutePoint
    ) -> Double {
        let latitudeScale = 111_132.0
        let longitudeScale = 111_320.0
            * cos(point.latitude * .pi / 180)
        let x = (point.longitude - lineStart.longitude) * longitudeScale
        let y = (point.latitude - lineStart.latitude) * latitudeScale
        let endX = (lineEnd.longitude - lineStart.longitude) * longitudeScale
        let endY = (lineEnd.latitude - lineStart.latitude) * latitudeScale
        let lengthSquared = endX * endX + endY * endY
        guard lengthSquared > 0 else { return hypot(x, y) }
        let projection = max(0, min(1, (x * endX + y * endY) / lengthSquared))
        return hypot(x - projection * endX, y - projection * endY)
    }

    private static func distance(
        _ lhs: TrackedLocationPoint,
        _ rhs: TrackedLocationPoint
    ) -> Double {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude).distance(
            from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        )
    }
}
