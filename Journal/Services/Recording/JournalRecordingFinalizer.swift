import CoreLocation
import Foundation
import OSLog
import SwiftData

nonisolated enum JournalRecordingFinalization: Sendable, Equatable {
    case visit
    case transit(RecordedTransitMode)
    case noUsableLocation
}

@MainActor
final class JournalRecordingFinalizer {
    private let motionService = JournalRecordingMotionService()

    func finalize(
        _ recording: ActiveJournalRecording,
        in modelContext: ModelContext
    ) async throws -> JournalRecordingFinalization {
        if let existing = try existingEntry(
            for: recording.id,
            in: modelContext
        ) {
            return existing.kind == .placeVisit
                ? .visit
                : .transit(
                    existing.transitDetails?.recordedTransitMode ?? .unknown
                )
        }
        let endedAt = recording.endedAt ?? .now
        let motion: [RecordedMotionObservation]
        do {
            motion = try await motionService.observations(
                from: recording.startedAt,
                to: endedAt
            )
        } catch {
            motion = []
            JournalRecordingLog.motion.error(
                "[Motion] history query failed: \(error.localizedDescription)"
            )
        }
        JournalRecordingLog.motion.info(
            "[Motion] queried \(recording.startedAt) → \(endedAt); \(motion.count) observations"
        )

        guard let classification = JournalRecordingClassifier.classify(
            points: recording.points,
            motion: motion
        ) else {
            return .noUsableLocation
        }

        switch classification {
        case .visit(let coordinate, let radius):
            JournalRecordingLog.classifier.info(
                "[Classifier] visit; coverage radius \(radius)m"
            )
            let location = await LocationService.shared.location(
                at: CLLocationCoordinate2D(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            )
            let place = try matchedPlace(
                at: coordinate,
                horizontalAccuracy: max(15, radius),
                in: modelContext
            )
            let draft = ResolvedPlaceVisitDraft(
                place: place,
                location: location,
                startTime: recording.startedAt,
                endTime: endedAt,
                timeConfidence: .explicit,
                people: [],
                candidates: [],
                unresolvedPeople: [],
                fieldReviews: [],
                entryKindReviewReason: nil
            )
            let entry = PlaceVisitEntryStore.makeEntry(
                draft: draft,
                rawInput: String(localized: "Recorded journal session")
            )
            entry.journalRecordingID = recording.id
            try PlaceVisitEntryStore.insert(entry, in: modelContext)
            return .visit

        case .transit(
            let origin,
            let destination,
            let route,
            let distanceMeters,
            let mode
        ):
            JournalRecordingLog.classifier.info(
                "[Classifier] transit; \(distanceMeters)m; dominant mode \(mode.rawValue)"
            )
            async let originLocation = LocationService.shared.location(
                at: CLLocationCoordinate2D(
                    latitude: origin.latitude,
                    longitude: origin.longitude
                )
            )
            async let destinationLocation = LocationService.shared.location(
                at: CLLocationCoordinate2D(
                    latitude: destination.latitude,
                    longitude: destination.longitude
                )
            )
            var fieldReviews: [TransitFieldReview] = []
            if mode == .unknown {
                fieldReviews.append(
                    TransitFieldReview(
                        field: .transitType,
                        reason: String(
                            localized: "The recording did not contain enough motion information to identify transportation."
                        )
                    )
                )
            }
            let draft = await ResolvedTransitDraft(
                transitType: mode.transitTypeName,
                originPlace: try matchedPlace(
                    at: origin,
                    horizontalAccuracy: 25,
                    in: modelContext
                ),
                originLocation: originLocation,
                destinationPlace: try matchedPlace(
                    at: destination,
                    horizontalAccuracy: 25,
                    in: modelContext
                ),
                destinationLocation: destinationLocation,
                startTime: recording.startedAt,
                endTime: endedAt,
                timeConfidence: .explicit,
                people: [],
                durationSource: .unresolved,
                originCandidates: [],
                destinationCandidates: [],
                unresolvedPeople: [],
                fieldReviews: fieldReviews
            )
            let entry = TransitEntryStore.makeEntry(
                draft: draft,
                rawInput: String(localized: "Recorded journal session")
            )
            entry.journalRecordingID = recording.id
            entry.transitDetails?.distanceMeters = distanceMeters
            entry.transitDetails?.recordedRoute = route
            entry.transitDetails?.recordedMotion = motion
            entry.transitDetails?.recordedTransitMode = mode
            try TransitEntryStore.insert(
                entry,
                refreshDistance: false,
                in: modelContext
            )
            return .transit(mode)
        }
    }

    private func matchedPlace(
        at point: RecordedRoutePoint,
        horizontalAccuracy: Double,
        in modelContext: ModelContext
    ) throws -> Place? {
        let places = try modelContext.fetch(FetchDescriptor<Place>())
        let coordinate = WorkoutCoordinateSnapshot(
            latitude: point.latitude,
            longitude: point.longitude,
            horizontalAccuracyMeters: horizontalAccuracy
        )
        guard case .matched(let place) = WorkoutPlaceMatcher.match(
            coordinate: coordinate,
            places: places
        ) else { return nil }
        return place
    }

    private func existingEntry(
        for recordingID: UUID,
        in modelContext: ModelContext
    ) throws -> LogEntry? {
        var descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate { entry in
                entry.journalRecordingID == recordingID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
