import CoreLocation
import CoreMotion
import Foundation
import SwiftData

nonisolated struct MotionActivitySample: Hashable, Sendable {
    let startTime: Date
    let confidenceRawValue: Int
    let isWalking: Bool
    let isRunning: Bool
    let isCycling: Bool
    let isAutomotive: Bool
    let isStationary: Bool
    let isUnknown: Bool
}

nonisolated struct MotionActivitySegment: Hashable, Sendable {
    let kind: MotionTransitKind
    let confidenceRawValue: Int
    let startTime: Date
    let endTime: Date
}

nonisolated enum MotionActivitySegmenter {
    static let maximumMergeGap: TimeInterval = 2 * 60
    static let minimumDuration: TimeInterval = 3 * 60

    static func segments(
        from samples: [MotionActivitySample]
    ) -> [MotionActivitySegment] {
        let ordered = samples.sorted { $0.startTime < $1.startTime }
        guard ordered.count > 1 else { return [] }

        var classified: [MotionActivitySegment] = []
        for (sample, next) in zip(ordered, ordered.dropFirst()) {
            guard next.startTime > sample.startTime,
                  let kind = kind(for: sample) else { continue }
            classified.append(
                MotionActivitySegment(
                    kind: kind,
                    confidenceRawValue: sample.confidenceRawValue,
                    startTime: sample.startTime,
                    endTime: next.startTime
                )
            )
        }

        var merged: [MotionActivitySegment] = []
        for segment in classified {
            if let last = merged.last,
               last.kind == segment.kind,
               segment.startTime.timeIntervalSince(last.endTime)
                    <= maximumMergeGap {
                merged[merged.count - 1] = MotionActivitySegment(
                    kind: last.kind,
                    confidenceRawValue: min(
                        last.confidenceRawValue,
                        segment.confidenceRawValue
                    ),
                    startTime: last.startTime,
                    endTime: segment.endTime
                )
            } else {
                merged.append(segment)
            }
        }
        return merged.filter {
            $0.endTime.timeIntervalSince($0.startTime) >= minimumDuration
        }
    }

    static func kind(
        for sample: MotionActivitySample
    ) -> MotionTransitKind? {
        guard sample.confidenceRawValue >= CMMotionActivityConfidence.medium
            .rawValue,
              !sample.isUnknown else {
            return nil
        }
        if sample.isAutomotive { return .automotive }
        if sample.isCycling { return .bicycle }
        if sample.isWalking, !sample.isRunning { return .walk }
        return nil
    }
}

@MainActor
final class MotionTransitDetectionService {
    static let shared = MotionTransitDetectionService()

    private let manager = CMMotionActivityManager()
    private var previousLiveSample: MotionActivitySample?
    private var liveModelContainer: ModelContainer?

    private init() {}

    func reconcile(in modelContext: ModelContext) async throws {
        try Self.persist(
            segments: try await historicalSegments(),
            in: modelContext
        )
    }

    func historicalSegments() async throws -> [MotionActivitySegment] {
        guard CMMotionActivityManager.isActivityAvailable() else { return [] }
        let end = Date.now
        let start = end.addingTimeInterval(-7 * 24 * 60 * 60)
        let samples = try await query(from: start, to: end)
        return MotionActivitySegmenter.segments(from: samples)
    }

    func startLiveUpdates(modelContainer: ModelContainer) {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        liveModelContainer = modelContainer
        manager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            let sample = Self.snapshot(activity)
            Task { @MainActor in
                defer { self.previousLiveSample = sample }
                guard let previous = self.previousLiveSample,
                      let modelContainer = self.liveModelContainer else {
                    return
                }
                let segments = MotionActivitySegmenter.segments(
                    from: [previous, sample]
                )
                guard !segments.isEmpty else { return }
                let maintenance = await JournalPersistenceActors.shared
                    .maintenance(
                        for: JournalModelContainerReference(modelContainer)
                    )
                await maintenance.persistMotion(segments)
            }
        }
    }

    func stopLiveUpdates() {
        manager.stopActivityUpdates()
        previousLiveSample = nil
        liveModelContainer = nil
    }

    private func query(
        from start: Date,
        to end: Date
    ) async throws -> [MotionActivitySample] {
        try await withCheckedThrowingContinuation { continuation in
            manager.queryActivityStarting(
                from: start,
                to: end,
                to: .main
            ) { activities, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(
                        returning: (activities ?? []).map(Self.snapshot)
                    )
                }
            }
        }
    }

    nonisolated static func persist(
        segments: [MotionActivitySegment],
        in modelContext: ModelContext
    ) throws {
        guard !segments.isEmpty else { return }
        let lowerBound = segments.map(\.startTime).min()?
            .addingTimeInterval(-30 * 60) ?? .distantPast
        let upperBound = segments.map(\.endTime).max()?
            .addingTimeInterval(30 * 60) ?? .distantFuture
        let entries = try modelContext.fetch(
            FetchDescriptor<LogEntry>(
                predicate: #Predicate { entry in
                    (entry.startTime ?? upperBound) <= upperBound
                        && (entry.endTime ?? lowerBound) >= lowerBound
                }
            )
        )
        let candidates = try modelContext.fetch(
            FetchDescriptor<AutomationCandidate>(
                predicate: #Predicate { candidate in
                    candidate.startTime <= upperBound
                        && (candidate.endTime ?? lowerBound) >= lowerBound
                }
            )
        )
        let observations = endpointObservations(
            entries: entries,
            candidates: candidates
        )

        for segment in segments {
            guard let origin = nearestObservation(
                to: segment.startTime,
                role: .departure,
                in: observations
            ),
            let destination = nearestObservation(
                to: segment.endTime,
                role: .arrival,
                in: observations
            ) else {
                continue
            }
            let distance = CLLocation(
                latitude: origin.location.latitude,
                longitude: origin.location.longitude
            ).distance(
                from: CLLocation(
                    latitude: destination.location.latitude,
                    longitude: destination.location.longitude
                )
            )
            guard distance >= 100,
                  !duplicatesExistingTransit(
                    segment: segment,
                    origin: origin.location,
                    destination: destination.location,
                    entries: entries
                  ) else {
                continue
            }

            _ = try AutomationCandidateStore.upsertMotion(
                MotionTransitDetection(
                    kind: segment.kind,
                    confidenceRawValue: segment.confidenceRawValue,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    originLocation: origin.location,
                    originPlaceID: origin.placeID,
                    destinationLocation: destination.location,
                    destinationPlaceID: destination.placeID
                ),
                in: modelContext
            )
        }
        if modelContext.hasChanges {
            try modelContext.save()
            NotificationCenter.default.post(
                name: .automationCandidatesDidChange,
                object: nil
            )
        }
    }

    private static func snapshot(
        _ activity: CMMotionActivity
    ) -> MotionActivitySample {
        MotionActivitySample(
            startTime: activity.startDate,
            confidenceRawValue: activity.confidence.rawValue,
            isWalking: activity.walking,
            isRunning: activity.running,
            isCycling: activity.cycling,
            isAutomotive: activity.automotive,
            isStationary: activity.stationary,
            isUnknown: activity.unknown
        )
    }
}

nonisolated private extension MotionTransitDetectionService {
    nonisolated enum EndpointRole: Sendable {
        case arrival
        case departure
    }

    struct EndpointObservation: Sendable {
        let date: Date
        let role: EndpointRole
        let location: Location
        let placeID: UUID?
    }

    static func endpointObservations(
        entries: [LogEntry],
        candidates: [AutomationCandidate]
    ) -> [EndpointObservation] {
        var result: [EndpointObservation] = []

        for candidate in candidates where candidate.kind == .visit {
            guard let endTime = candidate.endTime,
                  let location = candidate.visitLocation else { continue }
            result.append(
                EndpointObservation(
                    date: candidate.startTime,
                    role: .arrival,
                    location: location,
                    placeID: candidate.visitPlaceID
                )
            )
            result.append(
                EndpointObservation(
                    date: endTime,
                    role: .departure,
                    location: location,
                    placeID: candidate.visitPlaceID
                )
            )
        }

        for entry in entries {
            guard let start = entry.startTime,
                  let end = entry.endTime else { continue }
            switch entry.kind {
            case .placeVisit:
                let details = entry.placeVisitDetails
                guard let location = details?.location
                    ?? details?.place?.location else { continue }
                result.append(.init(
                    date: start,
                    role: .arrival,
                    location: location,
                    placeID: details?.place?.id
                ))
                result.append(.init(
                    date: end,
                    role: .departure,
                    location: location,
                    placeID: details?.place?.id
                ))
            case .transit:
                let details = entry.transitDetails
                if let location = details?.originLocation
                    ?? details?.originPlace?.location {
                    result.append(.init(
                        date: start,
                        role: .departure,
                        location: location,
                        placeID: details?.originPlace?.id
                    ))
                }
                if let location = details?.destinationLocation
                    ?? details?.destinationPlace?.location {
                    result.append(.init(
                        date: end,
                        role: .arrival,
                        location: location,
                        placeID: details?.destinationPlace?.id
                    ))
                }
            case .workout:
                let details = entry.workoutDetails
                if details?.movementKind == .moving {
                    if let location = details?.originLocation
                        ?? details?.originPlace?.location {
                        result.append(.init(
                            date: start,
                            role: .departure,
                            location: location,
                            placeID: details?.originPlace?.id
                        ))
                    }
                    if let location = details?.destinationLocation
                        ?? details?.destinationPlace?.location {
                        result.append(.init(
                            date: end,
                            role: .arrival,
                            location: location,
                            placeID: details?.destinationPlace?.id
                        ))
                    }
                } else if let location = details?.sourceLocation
                    ?? details?.place?.location {
                    result.append(.init(
                        date: start,
                        role: .arrival,
                        location: location,
                        placeID: details?.place?.id
                    ))
                    result.append(.init(
                        date: end,
                        role: .departure,
                        location: location,
                        placeID: details?.place?.id
                    ))
                }
            case .wakeUp:
                continue
            }
        }
        return result
    }

    static func nearestObservation(
        to date: Date,
        role: EndpointRole,
        in observations: [EndpointObservation]
    ) -> EndpointObservation? {
        observations
            .filter {
                $0.role == role
                    && abs($0.date.timeIntervalSince(date)) <= 30 * 60
            }
            .min {
                let left = abs($0.date.timeIntervalSince(date))
                let right = abs($1.date.timeIntervalSince(date))
                return left < right
            }
    }

    static func duplicatesExistingTransit(
        segment: MotionActivitySegment,
        origin: Location,
        destination: Location,
        entries: [LogEntry]
    ) -> Bool {
        let duration = segment.endTime.timeIntervalSince(segment.startTime)
        guard duration > 0 else { return true }
        return entries.contains { entry in
            guard entry.kind == .transit,
                  let start = entry.startTime,
                  let end = entry.endTime,
                  let details = entry.transitDetails,
                  let storedOrigin = details.originLocation
                    ?? details.originPlace?.location,
                  let storedDestination = details.destinationLocation
                    ?? details.destinationPlace?.location else {
                return false
            }
            let overlap = max(
                0,
                min(segment.endTime, end)
                    .timeIntervalSince(max(segment.startTime, start))
            )
            guard overlap / duration >= 0.7 else { return false }
            return locationsAreNear(origin, storedOrigin)
                && locationsAreNear(destination, storedDestination)
        }
    }

    static func locationsAreNear(_ lhs: Location, _ rhs: Location) -> Bool {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(
                from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
            ) <= 250
    }
}
