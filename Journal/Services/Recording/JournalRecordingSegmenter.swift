import CoreLocation
import Foundation

nonisolated struct JournalRecordingSegmentationConfiguration: Sendable {
    var maximumHorizontalAccuracyMeters = 120.0
    var genericVisitRadiusMeters = 70.0
    var maximumGenericVisitRadiusMeters = 110.0
    var accuracyRadiusMultiplier = 2.5
    var minimumSavedPlaceRadiusMeters = 50.0
    var savedPlaceMarginMeters = 30.0
    var minimumGenericVisitDuration: TimeInterval = 7 * 60
    var minimumSavedPlaceVisitDuration: TimeInterval = 4 * 60
    var minimumDwellFraction = 0.72
    var exitConfirmationDuration: TimeInterval = 90
    var immediateExitOvershootMeters = 125.0
    var precisePlaceAccuracyMeters = 25.0
    var homeEndpointRadiusMeters = 200.0
    var minimumBoundaryHomeVisitDuration: TimeInterval = 12 * 60
    var minimumTransitDistanceMeters = 60.0
    var minimumTransitDisplacementMeters = 45.0
    var minimumMotionSupportedTransitDuration: TimeInterval = 90
    var maximumMergeGap: TimeInterval = 3 * 60
    var visitEvidenceSearchMargin: TimeInterval = 5 * 60
    var minimumVisitEvidenceDuration: TimeInterval = 4 * 60
    var minimumVisitEvidenceCoverageFraction = 0.55
    var maximumVisitEvidenceAccuracyMeters = 150.0
    var motionMergeGap: TimeInterval = 2 * 60
    var minimumMotionSegmentDuration: TimeInterval = 3 * 60
    var minimumMotionConfidenceRawValue = 1
    var motionBoundarySnapThreshold: TimeInterval = 5 * 60
    var motionBoundaryOutsideMarginMeters = 30.0
}

nonisolated struct JournalRecordingVisitSegment: Sendable, Equatable {
    var startTime: Date
    var endTime: Date
    var coordinate: RecordedRoutePoint
    var radiusMeters: Double
    var placeID: UUID?
    var isHome: Bool
}

nonisolated struct JournalRecordingTransitSegment: Sendable, Equatable {
    var startTime: Date
    var endTime: Date
    var origin: RecordedRoutePoint
    var destination: RecordedRoutePoint
    var originPlaceID: UUID?
    var destinationPlaceID: UUID?
    var route: [RecordedRoutePoint]
    var distanceMeters: Double
    var mode: RecordedTransitMode
    var motion: [RecordedMotionObservation]
}

nonisolated enum JournalRecordingTimelineSegment: Sendable, Equatable {
    case visit(JournalRecordingVisitSegment)
    case transit(JournalRecordingTransitSegment)

    var startTime: Date {
        switch self {
        case .visit(let visit): visit.startTime
        case .transit(let transit): transit.startTime
        }
    }
}

nonisolated enum JournalRecordingSegmenter {
    static func segments(
        points: [TrackedLocationPoint],
        motion: [RecordedMotionObservation],
        places: [JournalRecordingPlaceRegion],
        visitEvidence: [JournalRecordingVisitEvidence] = [],
        configuration: JournalRecordingSegmentationConfiguration = .init()
    ) -> [JournalRecordingTimelineSegment] {
        let reliable = reliablePoints(points, configuration: configuration)
        guard !reliable.isEmpty else { return [] }

        let gpsVisits = detectedVisits(
            in: reliable,
            places: places,
            configuration: configuration
        )
        let visits = snappedVisitBoundaries(
            nonOverlappingVisits(
                mergedVisits(
                    gpsVisits + evidenceVisits(
                        visitEvidence,
                        in: reliable,
                        places: places,
                        configuration: configuration
                    ),
                    points: reliable,
                    configuration: configuration
                ),
                points: reliable
            ),
            motion: motion,
            points: reliable,
            configuration: configuration
        )
        guard !visits.isEmpty else {
            return fallbackSegments(
                points: reliable,
                motion: motion,
                places: places,
                configuration: configuration
            )
        }

        var result: [JournalRecordingTimelineSegment] = []
        var previousVisit: IndexedVisit?
        for (index, visit) in visits.enumerated() {
            let gapStart = previousVisit?.endIndex ?? reliable.startIndex
            let gapEnd = visit.startIndex
            let gapTransits = transitSegments(
                points: pointSlice(in: gapStart...gapEnd, from: reliable),
                motion: motion,
                originVisit: previousVisit,
                destinationVisit: visit,
                places: places,
                configuration: configuration
            )
            result.append(contentsOf: gapTransits.map {
                JournalRecordingTimelineSegment.transit($0)
            })

            let hasTransitBefore = result.last.map {
                if case .transit = $0 { true } else { false }
            } ?? false
            let hasPotentialTransitAfter = hasMeaningfulTransit(
                points: pointSlice(
                    in: visit.endIndex...(
                        index + 1 < visits.count
                            ? visits[index + 1].startIndex
                            : reliable.index(before: reliable.endIndex)
                    ),
                    from: reliable
                ),
                motion: motion,
                configuration: configuration
            )
            let isBoundaryHome = visit.segment.isHome
                && visit.segment.endTime.timeIntervalSince(
                    visit.segment.startTime
                ) < configuration.minimumBoundaryHomeVisitDuration
                && ((index == visits.startIndex && hasPotentialTransitAfter)
                    || (index == visits.index(before: visits.endIndex)
                        && hasTransitBefore))
            if !isBoundaryHome {
                result.append(.visit(visit.segment))
            }
            previousVisit = visit
        }

        if let previousVisit {
            let trailingTransits = transitSegments(
                points: pointSlice(
                    in: previousVisit.endIndex...reliable.index(
                        before: reliable.endIndex
                    ),
                    from: reliable
                ),
                motion: motion,
                originVisit: previousVisit,
                destinationVisit: nil,
                places: places,
                configuration: configuration
            )
            result.append(contentsOf: trailingTransits.map {
                JournalRecordingTimelineSegment.transit($0)
            })
        }
        return result.sorted { $0.startTime < $1.startTime }
    }

    private struct IndexedVisit {
        var startIndex: Int
        var endIndex: Int
        var segment: JournalRecordingVisitSegment
    }

    private static func reliablePoints(
        _ points: [TrackedLocationPoint],
        configuration: JournalRecordingSegmentationConfiguration
    ) -> [TrackedLocationPoint] {
        points.filter { point in
            point.latitude.isFinite
                && point.longitude.isFinite
                && (-90...90).contains(point.latitude)
                && (-180...180).contains(point.longitude)
                && point.horizontalAccuracy >= 0
                && point.horizontalAccuracy
                    <= configuration.maximumHorizontalAccuracyMeters
        }.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.horizontalAccuracy < rhs.horizontalAccuracy
            }
            return lhs.timestamp < rhs.timestamp
        }.reduce(into: []) { result, point in
            if result.last?.timestamp == point.timestamp { return }
            result.append(point)
        }
    }

    private static func detectedVisits(
        in points: [TrackedLocationPoint],
        places: [JournalRecordingPlaceRegion],
        configuration: JournalRecordingSegmentationConfiguration
    ) -> [IndexedVisit] {
        guard !points.isEmpty else { return [] }
        var result: [IndexedVisit] = []
        var startIndex = points.startIndex

        while startIndex < points.endIndex {
            let anchor = points[startIndex]
            let anchorPlace = match(
                point: anchor,
                places: places,
                configuration: configuration
            )
            let center = anchorPlace.map {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
            } ?? location(anchor)
            let radius = visitRadius(
                place: anchorPlace,
                accuracy: anchor.horizontalAccuracy,
                configuration: configuration
            )
            var lastInsideIndex = startIndex
            var firstOutsideIndex: Int?
            var scanIndex = points.index(after: startIndex)

            while scanIndex < points.endIndex {
                let point = points[scanIndex]
                let distance = location(point).distance(from: center)
                let preciseOtherPlace: JournalRecordingPlaceRegion? =
                    anchorPlace.flatMap { current in
                    guard point.horizontalAccuracy
                        <= configuration.precisePlaceAccuracyMeters,
                          let candidate = match(
                            point: point,
                            places: places,
                            configuration: configuration
                          ),
                          candidate.id != current.id else { return nil }
                        return candidate
                    }
                let isInside = distance <= radius && preciseOtherPlace == nil

                if isInside {
                    lastInsideIndex = scanIndex
                    firstOutsideIndex = nil
                } else {
                    if firstOutsideIndex == nil {
                        firstOutsideIndex = scanIndex
                    }
                    let outsideDuration = firstOutsideIndex.map {
                        point.timestamp.timeIntervalSince(points[$0].timestamp)
                    } ?? 0
                    if distance >= radius
                        + configuration.immediateExitOvershootMeters
                        || outsideDuration
                            >= configuration.exitConfirmationDuration {
                        break
                    }
                }
                scanIndex = points.index(after: scanIndex)
            }

            let duration = points[lastInsideIndex].timestamp
                .timeIntervalSince(anchor.timestamp)
            let minimumDuration = anchorPlace == nil
                ? configuration.minimumGenericVisitDuration
                : configuration.minimumSavedPlaceVisitDuration
            let candidatePoints = Array(points[startIndex...lastInsideIndex])
            let dwellFraction = coverageFraction(
                points: candidatePoints,
                center: center,
                radiusMeters: radius
            )
            if duration >= minimumDuration,
               dwellFraction >= configuration.minimumDwellFraction {
                let representative = representativePoint(candidatePoints)
                let representativeAccuracy = median(
                    candidatePoints.map(\.horizontalAccuracy)
                )
                let matchedPlace = match(
                    latitude: representative.latitude,
                    longitude: representative.longitude,
                    accuracy: representativeAccuracy,
                    places: places,
                    configuration: configuration
                ) ?? anchorPlace
                let distances = candidatePoints.map {
                    location($0).distance(
                        from: CLLocation(
                            latitude: representative.latitude,
                            longitude: representative.longitude
                        )
                    )
                }.sorted()
                let radiusIndex = min(
                    distances.count - 1,
                    max(0, Int(ceil(Double(distances.count) * 0.9)) - 1)
                )
                result.append(
                    IndexedVisit(
                        startIndex: startIndex,
                        endIndex: lastInsideIndex,
                        segment: JournalRecordingVisitSegment(
                            startTime: anchor.timestamp,
                            endTime: points[lastInsideIndex].timestamp,
                            coordinate: representative,
                            radiusMeters: distances[radiusIndex],
                            placeID: matchedPlace?.id,
                            isHome: matchedPlace?.isHome ?? false
                        )
                    )
                )
                startIndex = max(
                    points.index(after: lastInsideIndex),
                    firstOutsideIndex ?? points.index(after: lastInsideIndex)
                )
            } else {
                startIndex = points.index(after: startIndex)
            }
        }
        return result
    }

    private static func evidenceVisits(
        _ evidence: [JournalRecordingVisitEvidence],
        in points: [TrackedLocationPoint],
        places: [JournalRecordingPlaceRegion],
        configuration: JournalRecordingSegmentationConfiguration
    ) -> [IndexedVisit] {
        evidence.compactMap { evidence -> IndexedVisit? in
            guard evidence.endTime > evidence.startTime,
                  evidence.horizontalAccuracyMeters >= 0,
                  evidence.horizontalAccuracyMeters
                    <= configuration.maximumVisitEvidenceAccuracyMeters else {
                return nil
            }
            let evidencePoint = TrackedLocationPoint(
                latitude: evidence.latitude,
                longitude: evidence.longitude,
                timestamp: evidence.startTime,
                horizontalAccuracy: evidence.horizontalAccuracyMeters,
                altitude: nil,
                speed: nil,
                course: nil
            )
            let explicitPlace = evidence.placeID.flatMap { id in
                places.first { $0.id == id }
            }
            let matchedPlace = explicitPlace ?? match(
                point: evidencePoint,
                places: places,
                configuration: configuration
            )
            let center = matchedPlace.map {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
            } ?? location(evidencePoint)
            let radius = matchedPlace.map {
                visitRadius(
                    place: $0,
                    accuracy: evidence.horizontalAccuracyMeters,
                    configuration: configuration
                )
            } ?? min(
                configuration.maximumVisitEvidenceAccuracyMeters,
                max(
                    configuration.genericVisitRadiusMeters,
                    evidence.horizontalAccuracyMeters
                        * configuration.accuracyRadiusMultiplier
                )
            )
            let searchStart = evidence.startTime.addingTimeInterval(
                -configuration.visitEvidenceSearchMargin
            )
            let searchEnd = evidence.endTime.addingTimeInterval(
                configuration.visitEvidenceSearchMargin
            )
            let candidateIndices = points.indices.filter { index in
                let point = points[index]
                guard point.timestamp >= searchStart,
                      point.timestamp <= searchEnd,
                      location(point).distance(from: center) <= radius else {
                    return false
                }
                if point.horizontalAccuracy
                    <= configuration.precisePlaceAccuracyMeters,
                   let matchedPlace,
                   let other = match(
                    point: point,
                    places: places,
                    configuration: configuration
                   ), other.id != matchedPlace.id {
                    return false
                }
                return true
            }
            guard let firstIndex = candidateIndices.first,
                  let lastIndex = candidateIndices.last else { return nil }
            let candidatePoints = Array(points[firstIndex...lastIndex])
            let duration = points[lastIndex].timestamp.timeIntervalSince(
                points[firstIndex].timestamp
            )
            let evidenceDuration = evidence.endTime.timeIntervalSince(
                evidence.startTime
            )
            let requiredDwellDuration = max(
                configuration.minimumVisitEvidenceDuration,
                evidenceDuration
                    * configuration.minimumVisitEvidenceCoverageFraction
            )
            guard duration >= requiredDwellDuration,
                  coverageFraction(
                    points: candidatePoints,
                    center: center,
                    radiusMeters: radius
                  ) >= configuration.minimumVisitEvidenceCoverageFraction else {
                return nil
            }
            let representative = representativePoint(
                candidatePoints.filter {
                    location($0).distance(from: center) <= radius
                }
            )
            let finalPlace = matchedPlace ?? match(
                latitude: representative.latitude,
                longitude: representative.longitude,
                accuracy: median(candidatePoints.map(\.horizontalAccuracy)),
                places: places,
                configuration: configuration
            )
            let distances = candidatePoints.map {
                location($0).distance(
                    from: CLLocation(
                        latitude: representative.latitude,
                        longitude: representative.longitude
                    )
                )
            }.sorted()
            let radiusIndex = min(
                distances.count - 1,
                max(0, Int(ceil(Double(distances.count) * 0.9)) - 1)
            )
            return IndexedVisit(
                startIndex: firstIndex,
                endIndex: lastIndex,
                segment: JournalRecordingVisitSegment(
                    startTime: points[firstIndex].timestamp,
                    endTime: points[lastIndex].timestamp,
                    coordinate: representative,
                    radiusMeters: distances[radiusIndex],
                    placeID: finalPlace?.id,
                    isHome: finalPlace?.isHome ?? false
                )
            )
        }
    }

    private static func mergedVisits(
        _ visits: [IndexedVisit],
        points: [TrackedLocationPoint],
        configuration: JournalRecordingSegmentationConfiguration
    ) -> [IndexedVisit] {
        var result: [IndexedVisit] = []
        for visit in visits.sorted(by: {
            if $0.startIndex == $1.startIndex {
                return $0.endIndex < $1.endIndex
            }
            return $0.startIndex < $1.startIndex
        }) {
            guard let previous = result.last else {
                result.append(visit)
                continue
            }
            let gap = visit.segment.startTime.timeIntervalSince(
                previous.segment.endTime
            )
            let sameSavedPlace = previous.segment.placeID != nil
                && previous.segment.placeID == visit.segment.placeID
            let separation = distance(
                previous.segment.coordinate,
                visit.segment.coordinate
            )
            let sameGenericArea = previous.segment.placeID == nil
                && visit.segment.placeID == nil
                && separation <= max(
                    configuration.genericVisitRadiusMeters,
                    previous.segment.radiusMeters,
                    visit.segment.radiusMeters
                )
            guard gap <= configuration.maximumMergeGap,
                  sameSavedPlace || sameGenericArea else {
                result.append(visit)
                continue
            }

            let combinedPoints = Array(points[previous.startIndex...visit.endIndex])
            let representative = representativePoint(combinedPoints)
            let merged = JournalRecordingVisitSegment(
                startTime: previous.segment.startTime,
                endTime: visit.segment.endTime,
                coordinate: representative,
                radiusMeters: max(
                    previous.segment.radiusMeters,
                    visit.segment.radiusMeters
                ),
                placeID: previous.segment.placeID ?? visit.segment.placeID,
                isHome: previous.segment.isHome || visit.segment.isHome
            )
            result[result.index(before: result.endIndex)] = IndexedVisit(
                startIndex: previous.startIndex,
                endIndex: visit.endIndex,
                segment: merged
            )
        }
        return result
    }

    private static func snappedVisitBoundaries(
        _ visits: [IndexedVisit],
        motion: [RecordedMotionObservation],
        points: [TrackedLocationPoint],
        configuration: JournalRecordingSegmentationConfiguration
    ) -> [IndexedVisit] {
        guard let firstPoint = points.first,
              let lastPoint = points.last else { return visits }
        let runs = motionRuns(
            motion,
            from: firstPoint.timestamp,
            to: lastPoint.timestamp,
            configuration: configuration
        )
        guard !runs.isEmpty else { return visits }

        return visits.map { original in
            var visit = original
            let relevantRuns = runs.filter {
                motionRunLeavesVisit(
                    $0,
                    visit: visit,
                    points: points,
                    configuration: configuration
                )
            }
            let minimumDuration = visit.segment.placeID == nil
                ? configuration.minimumGenericVisitDuration
                : configuration.minimumSavedPlaceVisitDuration

            if let arrival = relevantRuns.min(by: {
                abs($0.endTime.timeIntervalSince(visit.segment.startTime))
                    < abs($1.endTime.timeIntervalSince(visit.segment.startTime))
            }), abs(arrival.endTime.timeIntervalSince(visit.segment.startTime))
                <= configuration.motionBoundarySnapThreshold,
               visit.segment.endTime.timeIntervalSince(arrival.endTime)
                >= minimumDuration {
                visit.segment.startTime = arrival.endTime
                visit.startIndex = nearestPointIndex(
                    to: arrival.endTime,
                    in: points
                )
            }

            if let departure = relevantRuns.min(by: {
                abs($0.startTime.timeIntervalSince(visit.segment.endTime))
                    < abs($1.startTime.timeIntervalSince(visit.segment.endTime))
            }), abs(departure.startTime.timeIntervalSince(visit.segment.endTime))
                <= configuration.motionBoundarySnapThreshold,
               departure.startTime.timeIntervalSince(visit.segment.startTime)
                >= minimumDuration {
                visit.segment.endTime = departure.startTime
                visit.endIndex = nearestPointIndex(
                    to: departure.startTime,
                    in: points
                )
            }
            return visit
        }
    }

    private static func nonOverlappingVisits(
        _ visits: [IndexedVisit],
        points: [TrackedLocationPoint]
    ) -> [IndexedVisit] {
        var result: [IndexedVisit] = []
        for var visit in visits {
            guard var previous = result.last,
                  visit.startIndex <= previous.endIndex else {
                result.append(visit)
                continue
            }

            let lower = max(previous.startIndex, visit.startIndex)
            let upper = min(previous.endIndex, visit.endIndex)
            guard lower <= upper else {
                result.append(visit)
                continue
            }
            let previousCenter = CLLocation(
                latitude: previous.segment.coordinate.latitude,
                longitude: previous.segment.coordinate.longitude
            )
            let currentCenter = CLLocation(
                latitude: visit.segment.coordinate.latitude,
                longitude: visit.segment.coordinate.longitude
            )
            let boundary = (lower...upper).first { index in
                location(points[index]).distance(from: currentCenter)
                    < location(points[index]).distance(from: previousCenter)
            } ?? lower + (upper - lower) / 2

            guard boundary > previous.startIndex,
                  boundary < visit.endIndex else {
                let previousDuration = previous.segment.endTime
                    .timeIntervalSince(previous.segment.startTime)
                let currentDuration = visit.segment.endTime
                    .timeIntervalSince(visit.segment.startTime)
                if currentDuration > previousDuration {
                    result[result.index(before: result.endIndex)] = visit
                }
                continue
            }

            previous.endIndex = boundary
            previous.segment.endTime = points[boundary].timestamp
            visit.startIndex = boundary
            visit.segment.startTime = points[boundary].timestamp
            result[result.index(before: result.endIndex)] = previous
            result.append(visit)
        }
        return result
    }

    private static func motionRunLeavesVisit(
        _ run: MotionRun,
        visit: IndexedVisit,
        points: [TrackedLocationPoint],
        configuration: JournalRecordingSegmentationConfiguration
    ) -> Bool {
        let samples = timeSlice(
            around: run.startTime...run.endTime,
            from: points
        )
        guard samples.count > 1,
              JournalRecordingClassifier.routeDistance(samples)
                >= configuration.minimumTransitDistanceMeters else {
            return false
        }
        let center = CLLocation(
            latitude: visit.segment.coordinate.latitude,
            longitude: visit.segment.coordinate.longitude
        )
        let envelope = max(
            configuration.genericVisitRadiusMeters,
            visit.segment.radiusMeters
                + configuration.motionBoundaryOutsideMarginMeters
        )
        return samples.contains {
            location($0).distance(from: center) > envelope
        }
    }

    private static func fallbackSegments(
        points: [TrackedLocationPoint],
        motion: [RecordedMotionObservation],
        places: [JournalRecordingPlaceRegion],
        configuration: JournalRecordingSegmentationConfiguration
    ) -> [JournalRecordingTimelineSegment] {
        guard let classification = JournalRecordingClassifier.classify(
            points: points,
            motion: motion,
            placeRegions: places
        ) else { return [] }
        switch classification {
        case .visit(let coordinate, let radiusMeters):
            let accuracy = median(points.map(\.horizontalAccuracy))
            let place = match(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                accuracy: accuracy,
                places: places,
                configuration: configuration
            )
            return [
                .visit(
                    JournalRecordingVisitSegment(
                        startTime: points[0].timestamp,
                        endTime: points[points.count - 1].timestamp,
                        coordinate: coordinate,
                        radiusMeters: radiusMeters,
                        placeID: place?.id,
                        isHome: place?.isHome ?? false
                    )
                )
            ]
        case .transit(
            _,
            _,
            _,
            _,
            _
        ):
            return transitSegments(
                points: points,
                motion: motion,
                originVisit: nil,
                destinationVisit: nil,
                places: places,
                configuration: configuration
            ).map { .transit($0) }
        }
    }

    private struct MotionRun {
        var startTime: Date
        var endTime: Date
        var mode: RecordedTransitMode
    }

    private static func transitSegments(
        points: [TrackedLocationPoint],
        motion: [RecordedMotionObservation],
        originVisit: IndexedVisit?,
        destinationVisit: IndexedVisit?,
        places: [JournalRecordingPlaceRegion],
        configuration: JournalRecordingSegmentationConfiguration
    ) -> [JournalRecordingTransitSegment] {
        let connectsDistinctVisits = if let originVisit, let destinationVisit {
            originVisit.segment.placeID != destinationVisit.segment.placeID
                || distance(
                    originVisit.segment.coordinate,
                    destinationVisit.segment.coordinate
                ) >= 20
        } else {
            false
        }
        guard points.count > 1 else { return [] }
        let gapStart = originVisit?.segment.endTime ?? points[0].timestamp
        let gapEnd = destinationVisit?.segment.startTime
            ?? points[points.count - 1].timestamp
        guard gapEnd > gapStart else { return [] }

        var runs = motionRuns(
            motion,
            from: gapStart,
            to: gapEnd,
            configuration: configuration
        ).filter { run in
            let runPoints = timeSlice(
                around: run.startTime...run.endTime,
                from: points
            )
            return hasMeaningfulTransit(
                points: runPoints,
                motion: motion,
                configuration: configuration
            )
        }
        if runs.isEmpty {
            guard connectsDistinctVisits || hasMeaningfulTransit(
                points: points,
                motion: motion,
                configuration: configuration
            ) else { return [] }
            let mode = JournalRecordingClassifier.dominantMode(
                motion: overlappingMotion(motion, from: gapStart, to: gapEnd),
                points: points
            )
            return makeTransitSegment(
                points: points,
                motion: motion,
                startTime: gapStart,
                endTime: gapEnd,
                mode: mode,
                originVisit: originVisit,
                destinationVisit: destinationVisit,
                originOverride: nil,
                destinationOverride: nil,
                places: places,
                configuration: configuration
            ).map { [$0] } ?? []
        }

        runs[0].startTime = gapStart
        for index in runs.indices.dropFirst() {
            let previousIndex = runs.index(before: index)
            let boundary = runs[previousIndex].endTime >= runs[index].startTime
                ? runs[index].startTime
                : Date(
                    timeIntervalSinceReferenceDate: (
                        runs[previousIndex].endTime
                            .timeIntervalSinceReferenceDate
                            + runs[index].startTime
                                .timeIntervalSinceReferenceDate
                    ) / 2
                )
            runs[previousIndex].endTime = boundary
            runs[index].startTime = boundary
        }
        runs[runs.index(before: runs.endIndex)].endTime = gapEnd

        let boundaryPoints = runs.dropLast().map { run in
            representativePoint(
                pointsNear(run.endTime, from: points, maximumCount: 4)
            )
        }
        return runs.indices.compactMap { index in
            let run = runs[index]
            return makeTransitSegment(
                points: timeSlice(
                    around: run.startTime...run.endTime,
                    from: points
                ),
                motion: motion,
                startTime: run.startTime,
                endTime: run.endTime,
                mode: run.mode,
                originVisit: index == runs.startIndex ? originVisit : nil,
                destinationVisit: index == runs.index(before: runs.endIndex)
                    ? destinationVisit
                    : nil,
                originOverride: index == runs.startIndex
                    ? nil
                    : boundaryPoints[index - 1],
                destinationOverride: index == runs.index(before: runs.endIndex)
                    ? nil
                    : boundaryPoints[index],
                places: places,
                configuration: configuration
            )
        }
    }

    private static func makeTransitSegment(
        points: [TrackedLocationPoint],
        motion: [RecordedMotionObservation],
        startTime: Date,
        endTime: Date,
        mode: RecordedTransitMode,
        originVisit: IndexedVisit?,
        destinationVisit: IndexedVisit?,
        originOverride: RecordedRoutePoint?,
        destinationOverride: RecordedRoutePoint?,
        places: [JournalRecordingPlaceRegion],
        configuration: JournalRecordingSegmentationConfiguration
    ) -> JournalRecordingTransitSegment? {
        guard points.count > 1, endTime > startTime else { return nil }
        let segmentMotion = overlappingMotion(
            motion,
            from: startTime,
            to: endTime
        )
        let originFallback = representativePoint(Array(points.prefix(3)))
        let destinationFallback = representativePoint(Array(points.suffix(3)))
        let leadingHome = originVisit == nil
            ? homeNear(
                originFallback,
                places: places,
                configuration: configuration
            )
            : nil
        let trailingHome = destinationVisit == nil
            ? homeNear(
                destinationFallback,
                places: places,
                configuration: configuration
            )
            : nil
        let originPlace = originVisit?.segment.placeID.flatMap { id in
            places.first { $0.id == id }
        } ?? (originOverride == nil ? leadingHome ?? match(
            latitude: originFallback.latitude,
            longitude: originFallback.longitude,
            accuracy: median(Array(points.prefix(3)).map(\.horizontalAccuracy)),
            places: places,
            configuration: configuration
        ) : nil)
        let destinationPlace = destinationVisit?.segment.placeID.flatMap { id in
            places.first { $0.id == id }
        } ?? (destinationOverride == nil ? trailingHome ?? match(
            latitude: destinationFallback.latitude,
            longitude: destinationFallback.longitude,
            accuracy: median(Array(points.suffix(3)).map(\.horizontalAccuracy)),
            places: places,
            configuration: configuration
        ) : nil)
        let origin = originPlace.map {
            routePoint(for: $0, timestamp: startTime)
        } ?? originVisit?.segment.coordinate ?? originOverride ?? originFallback
        let destination = destinationPlace.map {
            routePoint(for: $0, timestamp: endTime)
        } ?? destinationVisit?.segment.coordinate
            ?? destinationOverride ?? destinationFallback
        var route = JournalRecordingClassifier.denoisedRoute(points)
        if route.isEmpty {
            route = [origin, destination]
        } else {
            if let first = route.first, distance(first, origin) > 5 {
                route.insert(origin, at: route.startIndex)
            } else {
                route[route.startIndex] = origin
            }
            if let last = route.last, distance(last, destination) > 5 {
                route.append(destination)
            } else {
                route[route.index(before: route.endIndex)] = destination
            }
        }

        return JournalRecordingTransitSegment(
            startTime: startTime,
            endTime: endTime,
            origin: origin,
            destination: destination,
            originPlaceID: originPlace?.id ?? originVisit?.segment.placeID,
            destinationPlaceID: destinationPlace?.id
                ?? destinationVisit?.segment.placeID,
            route: route,
            distanceMeters: JournalRecordingClassifier.routeDistance(points),
            mode: mode,
            motion: segmentMotion
        )
    }

    private static func motionRuns(
        _ motion: [RecordedMotionObservation],
        from startTime: Date,
        to endTime: Date,
        configuration: JournalRecordingSegmentationConfiguration
    ) -> [MotionRun] {
        let classified = motion.compactMap { observation -> MotionRun? in
            guard observation.confidenceRawValue
                >= configuration.minimumMotionConfidenceRawValue else {
                return nil
            }
            let mode: RecordedTransitMode? = switch observation.kind {
            case .walking, .running: .walking
            case .cycling: .cycling
            case .automotive: .automotive
            case .stationary, .unknown: nil
            }
            guard let mode else { return nil }
            let clippedStart = max(startTime, observation.startTime)
            let clippedEnd = min(endTime, observation.endTime)
            guard clippedEnd > clippedStart else { return nil }
            return MotionRun(
                startTime: clippedStart,
                endTime: clippedEnd,
                mode: mode
            )
        }.sorted { $0.startTime < $1.startTime }

        var merged: [MotionRun] = []
        for run in classified {
            if let previous = merged.last,
               previous.mode == run.mode,
               run.startTime.timeIntervalSince(previous.endTime)
                    <= configuration.motionMergeGap {
                merged[merged.index(before: merged.endIndex)].endTime = max(
                    previous.endTime,
                    run.endTime
                )
            } else {
                merged.append(run)
            }
        }
        return merged.filter {
            $0.endTime.timeIntervalSince($0.startTime)
                >= configuration.minimumMotionSegmentDuration
        }
    }

    private static func hasMeaningfulTransit(
        points: [TrackedLocationPoint],
        motion: [RecordedMotionObservation],
        configuration: JournalRecordingSegmentationConfiguration
    ) -> Bool {
        guard points.count > 1 else { return false }
        let routeDistance = JournalRecordingClassifier.routeDistance(points)
        let displacement = location(points[0]).distance(
            from: location(points[points.count - 1])
        )
        let segmentMotion = overlappingMotion(
            motion,
            from: points[0].timestamp,
            to: points[points.count - 1].timestamp
        )
        let movementDuration = JournalRecordingClassifier
            .sustainedMovementDuration(segmentMotion)
        return routeDistance >= configuration.minimumTransitDistanceMeters
            || displacement
                >= configuration.minimumTransitDisplacementMeters
            || (movementDuration
                >= configuration.minimumMotionSupportedTransitDuration
                && routeDistance
                    >= configuration.minimumTransitDisplacementMeters)
    }

    private static func visitRadius(
        place: JournalRecordingPlaceRegion?,
        accuracy: Double,
        configuration: JournalRecordingSegmentationConfiguration
    ) -> Double {
        if let place {
            return max(
                configuration.minimumSavedPlaceRadiusMeters,
                place.radiusMeters + configuration.savedPlaceMarginMeters
            )
        }
        return min(
            configuration.maximumGenericVisitRadiusMeters,
            max(
                configuration.genericVisitRadiusMeters,
                accuracy * configuration.accuracyRadiusMultiplier
            )
        )
    }

    private static func match(
        point: TrackedLocationPoint,
        places: [JournalRecordingPlaceRegion],
        configuration: JournalRecordingSegmentationConfiguration
    ) -> JournalRecordingPlaceRegion? {
        match(
            latitude: point.latitude,
            longitude: point.longitude,
            accuracy: point.horizontalAccuracy,
            places: places,
            configuration: configuration
        )
    }

    private static func match(
        latitude: Double,
        longitude: Double,
        accuracy: Double,
        places: [JournalRecordingPlaceRegion],
        configuration: JournalRecordingSegmentationConfiguration
    ) -> JournalRecordingPlaceRegion? {
        let candidateLocation = CLLocation(
            latitude: latitude,
            longitude: longitude
        )
        let candidates = places.compactMap { place -> (JournalRecordingPlaceRegion, Double)? in
            let distance = candidateLocation.distance(
                from: CLLocation(
                    latitude: place.latitude,
                    longitude: place.longitude
                )
            )
            let radius = max(
                configuration.minimumSavedPlaceRadiusMeters,
                place.radiusMeters + configuration.savedPlaceMarginMeters
            )
            guard distance <= radius else { return nil }
            return (place, distance)
        }.sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0.id.uuidString < rhs.0.id.uuidString }
            return lhs.1 < rhs.1
        }
        guard let nearest = candidates.first else { return nil }
        guard candidates.count > 1 else { return nearest.0 }
        let requiredSeparation = min(25, max(5, accuracy * 0.5))
        return candidates[1].1 - nearest.1 >= requiredSeparation
            ? nearest.0
            : nil
    }

    private static func homeNear(
        _ point: RecordedRoutePoint,
        places: [JournalRecordingPlaceRegion],
        configuration: JournalRecordingSegmentationConfiguration
    ) -> JournalRecordingPlaceRegion? {
        let candidate = CLLocation(
            latitude: point.latitude,
            longitude: point.longitude
        )
        return places.filter(\.isHome).compactMap { place in
            let distance = candidate.distance(
                from: CLLocation(
                    latitude: place.latitude,
                    longitude: place.longitude
                )
            )
            return distance <= configuration.homeEndpointRadiusMeters
                ? (place, distance)
                : nil
        }.min { $0.1 < $1.1 }?.0
    }

    private static func representativePoint(
        _ points: [TrackedLocationPoint]
    ) -> RecordedRoutePoint {
        let weighted = points.reduce(
            into: (latitude: 0.0, longitude: 0.0, weight: 0.0)
        ) { result, point in
            let accuracy = max(5, point.horizontalAccuracy)
            let weight = 1 / (accuracy * accuracy)
            result.latitude += point.latitude * weight
            result.longitude += point.longitude * weight
            result.weight += weight
        }
        let midpoint = points[points.count / 2]
        return RecordedRoutePoint(
            latitude: weighted.latitude / weighted.weight,
            longitude: weighted.longitude / weighted.weight,
            timestamp: midpoint.timestamp
        )
    }

    private static func coverageFraction(
        points: [TrackedLocationPoint],
        center: CLLocation,
        radiusMeters: Double
    ) -> Double {
        guard points.count > 1 else { return 1 }
        let weights = temporalWeights(points)
        let total = weights.reduce(0, +)
        guard total > 0 else { return 1 }
        let covered = zip(points, weights).reduce(0.0) { result, pair in
            location(pair.0).distance(from: center) <= radiusMeters
                ? result + pair.1
                : result
        }
        return min(1, covered / total)
    }

    private static func temporalWeights(
        _ points: [TrackedLocationPoint]
    ) -> [TimeInterval] {
        guard points.count > 1 else { return [1] }
        return points.indices.map { index in
            let previous = index > points.startIndex
                ? points[index].timestamp.timeIntervalSince(
                    points[index - 1].timestamp
                ) / 2
                : 0
            let next = index < points.index(before: points.endIndex)
                ? points[index + 1].timestamp.timeIntervalSince(
                    points[index].timestamp
                ) / 2
                : 0
            return max(0, previous) + max(0, next)
        }
    }

    private static func overlappingMotion(
        _ motion: [RecordedMotionObservation],
        from start: Date,
        to end: Date
    ) -> [RecordedMotionObservation] {
        motion.compactMap { observation in
            let clippedStart = max(start, observation.startTime)
            let clippedEnd = min(end, observation.endTime)
            guard clippedEnd > clippedStart else { return nil }
            return RecordedMotionObservation(
                startTime: clippedStart,
                endTime: clippedEnd,
                kind: observation.kind,
                confidenceRawValue: observation.confidenceRawValue
            )
        }
    }

    private static func pointSlice(
        in range: ClosedRange<Int>,
        from points: [TrackedLocationPoint]
    ) -> [TrackedLocationPoint] {
        guard !points.isEmpty else { return [] }
        let lower = max(points.startIndex, min(range.lowerBound, points.endIndex - 1))
        let upper = max(lower, min(range.upperBound, points.endIndex - 1))
        return Array(points[lower...upper])
    }

    /// Returns samples inside a time range plus the closest sample on either
    /// side. Including the boundary neighbors keeps sparse Core Location
    /// delivery from producing disconnected routes at motion transitions.
    private static func timeSlice(
        around range: ClosedRange<Date>,
        from points: [TrackedLocationPoint]
    ) -> [TrackedLocationPoint] {
        guard !points.isEmpty else { return [] }
        var indices = points.indices.filter {
            range.contains(points[$0].timestamp)
        }
        if let before = points.indices.last(where: {
            points[$0].timestamp < range.lowerBound
        }) {
            indices.append(before)
        }
        if let after = points.indices.first(where: {
            points[$0].timestamp > range.upperBound
        }) {
            indices.append(after)
        }
        if indices.isEmpty {
            indices = points.indices.sorted {
                abs(points[$0].timestamp.timeIntervalSince(range.lowerBound))
                    < abs(points[$1].timestamp.timeIntervalSince(range.lowerBound))
            }.prefix(2).map { $0 }
        }
        return Set(indices).sorted().map { points[$0] }
    }

    private static func pointsNear(
        _ date: Date,
        from points: [TrackedLocationPoint],
        maximumCount: Int
    ) -> [TrackedLocationPoint] {
        points.sorted {
            abs($0.timestamp.timeIntervalSince(date))
                < abs($1.timestamp.timeIntervalSince(date))
        }.prefix(max(1, maximumCount)).sorted {
            $0.timestamp < $1.timestamp
        }
    }

    private static func nearestPointIndex(
        to date: Date,
        in points: [TrackedLocationPoint]
    ) -> Int {
        points.indices.min {
            abs(points[$0].timestamp.timeIntervalSince(date))
                < abs(points[$1].timestamp.timeIntervalSince(date))
        } ?? points.startIndex
    }

    private static func routePoint(
        for place: JournalRecordingPlaceRegion,
        timestamp: Date
    ) -> RecordedRoutePoint {
        RecordedRoutePoint(
            latitude: place.latitude,
            longitude: place.longitude,
            timestamp: timestamp
        )
    }

    private static func location(_ point: TrackedLocationPoint) -> CLLocation {
        CLLocation(latitude: point.latitude, longitude: point.longitude)
    }

    private static func distance(
        _ lhs: RecordedRoutePoint,
        _ rhs: RecordedRoutePoint
    ) -> Double {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude).distance(
            from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let ordered = values.sorted()
        return ordered.isEmpty ? 0 : ordered[ordered.count / 2]
    }
}
