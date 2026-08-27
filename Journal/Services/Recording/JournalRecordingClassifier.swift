import CoreLocation
import Foundation
import OSLog

nonisolated struct JournalRecordingClassificationConfiguration: Sendable {
    var maximumHorizontalAccuracy = 120.0
    var visitCoverageFraction = 0.9
    var minimumStrongTransitDistanceMeters = 150.0
    var minimumMotionSupportedTransitDistanceMeters = 75.0
    var minimumSparseTransitDistanceMeters = 40.0
    var maximumVisitDistanceMeters = 75.0
    var minimumVisitDwellFraction = 0.85
    var minimumSupportedMovementDuration: TimeInterval = 60
    var minimumSparseMovementDuration: TimeInterval = 120
    var movementMergeGap: TimeInterval = 15
    var speedSampleMergeGap: TimeInterval = 90
    var minimumMovingSpeedMetersPerSecond = 0.5
    var maximumPlausibleSpeedMetersPerSecond = 80.0
    var baseDwellRadiusMeters = 40.0
    var maximumDwellRadiusMeters = 60.0
    var dwellAccuracyMultiplier = 2.0
    var maximumDwellCandidateCount = 64
    var minimumRouteSimplificationToleranceMeters = 12.0
    var maximumRouteSimplificationToleranceMeters = 35.0
    var routeSimplificationAccuracyMultiplier = 1.5
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
        guard !reliable.isEmpty else { return nil }

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
        let traveledDistance = routeDistance(
            reliable,
            configuration: configuration
        )
        let movementDuration = max(
            sustainedMovementDuration(
                motion,
                minimumConfidenceRawValue:
                    configuration.minimumMotionConfidenceRawValue,
                mergeGap: configuration.movementMergeGap
            ),
            sustainedSpeedMovementDuration(
                reliable,
                configuration: configuration
            )
        )
        let dwellFraction = dominantDwellFraction(
            reliable,
            configuration: configuration
        )

        let hasStrongRoute = traveledDistance
            >= configuration.minimumStrongTransitDistanceMeters
        let hasMotionSupportedRoute = traveledDistance
            >= configuration.minimumMotionSupportedTransitDistanceMeters
            && movementDuration
                >= configuration.minimumSupportedMovementDuration
        let hasSparseMotionSupportedRoute = traveledDistance
            >= configuration.minimumSparseTransitDistanceMeters
            && movementDuration
                >= configuration.minimumSparseMovementDuration
        let isTransit = hasStrongRoute
            || hasMotionSupportedRoute
            || hasSparseMotionSupportedRoute
        let isVisit = traveledDistance
            < configuration.maximumVisitDistanceMeters
            && dwellFraction >= configuration.minimumVisitDwellFraction
            && movementDuration
                < configuration.minimumSupportedMovementDuration
        JournalRecordingLog.classifier.info(
            "[Classifier] confirmed path \(traveledDistance)m; sustained movement \(movementDuration)s; dominant dwell \(dwellFraction)"
        )

        if !isTransit, isVisit {
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

    static func sustainedMovementDuration(
        _ motion: [RecordedMotionObservation],
        minimumConfidenceRawValue: Int = 1,
        mergeGap: TimeInterval = 15
    ) -> TimeInterval {
        let intervals = motion.compactMap { observation -> DateInterval? in
            guard observation.confidenceRawValue >= minimumConfidenceRawValue,
                  observation.endTime > observation.startTime else { return nil }
            switch observation.kind {
            case .walking, .running, .cycling, .automotive:
                return DateInterval(
                    start: observation.startTime,
                    end: observation.endTime
                )
            case .stationary, .unknown:
                return nil
            }
        }.sorted { $0.start < $1.start }
        guard var current = intervals.first else { return 0 }

        var longest = current.duration
        for interval in intervals.dropFirst() {
            if interval.start.timeIntervalSince(current.end) <= mergeGap {
                current = DateInterval(
                    start: current.start,
                    end: max(current.end, interval.end)
                )
            } else {
                longest = max(longest, current.duration)
                current = interval
            }
        }
        return max(longest, current.duration)
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

        let speeds = points.compactMap(\.speed).filter { $0 >= 0.5 && $0 < 80 }
        guard !speeds.isEmpty else { return .unknown }
        let medianSpeed = speeds.sorted()[speeds.count / 2]
        if medianSpeed <= 2.7 { return .walking }
        if medianSpeed <= 10 { return .cycling }
        // High speed alone is deliberately not treated as automotive.
        return .unknown
    }

    static func routeDistance(
        _ points: [TrackedLocationPoint],
        configuration: JournalRecordingClassificationConfiguration = .init()
    ) -> Double {
        guard points.count > 1 else { return 0 }
        let accuracies = points.map(\.horizontalAccuracy).sorted()
        let medianAccuracy = accuracies[accuracies.count / 2]
        let tolerance = min(
            configuration.maximumRouteSimplificationToleranceMeters,
            max(
                configuration.minimumRouteSimplificationToleranceMeters,
                medianAccuracy
                    * configuration.routeSimplificationAccuracyMultiplier
            )
        )
        let confirmedRoute = simplify(
            points.map {
                RecordedRoutePoint(
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    timestamp: $0.timestamp
                )
            },
            toleranceMeters: tolerance
        )
        return zip(confirmedRoute, confirmedRoute.dropFirst()).reduce(0) {
            distance, pair in
            distance + CLLocation(
                latitude: pair.0.latitude,
                longitude: pair.0.longitude
            ).distance(
                from: CLLocation(
                    latitude: pair.1.latitude,
                    longitude: pair.1.longitude
                )
            )
        }
    }

    static func dominantDwellFraction(
        _ points: [TrackedLocationPoint],
        configuration: JournalRecordingClassificationConfiguration = .init()
    ) -> Double {
        guard !points.isEmpty else { return 0 }
        guard points.count > 1 else { return 1 }

        let accuracies = points.map(\.horizontalAccuracy).sorted()
        let medianAccuracy = accuracies[accuracies.count / 2]
        let dwellRadius = min(
            configuration.maximumDwellRadiusMeters,
            max(
                configuration.baseDwellRadiusMeters,
                medianAccuracy * configuration.dwellAccuracyMultiplier
            )
        )
        let weights = temporalWeights(points)
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return 1 }

        let maximumCandidateCount = max(
            1,
            configuration.maximumDwellCandidateCount
        )
        let stride = max(
            1,
            Int(
                ceil(
                    Double(points.count)
                        / Double(maximumCandidateCount)
                )
            )
        )
        var candidates = Swift.stride(
            from: 0,
            to: points.count,
            by: stride
        ).map { points[$0] }
        candidates.append(medianPoint(points))

        let greatestDwellWeight = candidates.map { candidate in
            zip(points, weights).reduce(0.0) { result, pair in
                distance(pair.0, candidate) <= dwellRadius
                    ? result + pair.1
                    : result
            }
        }.max() ?? 0
        return min(1, greatestDwellWeight / totalWeight)
    }

    private static func sustainedSpeedMovementDuration(
        _ points: [TrackedLocationPoint],
        configuration: JournalRecordingClassificationConfiguration
    ) -> TimeInterval {
        let moving = points.filter { point in
            guard let speed = point.speed else { return false }
            return speed >= configuration.minimumMovingSpeedMetersPerSecond
                && speed < configuration.maximumPlausibleSpeedMetersPerSecond
        }
        guard let first = moving.first else { return 0 }

        var runStart = first.timestamp
        var previous = first.timestamp
        var longest: TimeInterval = 0
        for point in moving.dropFirst() {
            if point.timestamp.timeIntervalSince(previous)
                > configuration.speedSampleMergeGap {
                longest = max(longest, previous.timeIntervalSince(runStart))
                runStart = point.timestamp
            }
            previous = point.timestamp
        }
        return max(longest, previous.timeIntervalSince(runStart))
    }

    private static func temporalWeights(
        _ points: [TrackedLocationPoint]
    ) -> [TimeInterval] {
        guard points.count > 1 else { return [1] }
        return points.indices.map { index in
            let previousHalf = index > points.startIndex
                ? max(
                    0,
                    points[index].timestamp.timeIntervalSince(
                        points[index - 1].timestamp
                    ) / 2
                )
                : 0
            let nextHalf = index < points.index(before: points.endIndex)
                ? max(
                    0,
                    points[index + 1].timestamp.timeIntervalSince(
                        points[index].timestamp
                    ) / 2
                )
                : 0
            return previousHalf + nextHalf
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
