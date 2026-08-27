import CoreLocation
import Foundation
import SwiftData

nonisolated struct VisitDetectionSnapshot: Hashable, Sendable {
    let arrivalDate: Date
    let departureDate: Date?
    let latitude: Double
    let longitude: Double
    let horizontalAccuracyMeters: Double

    var location: Location {
        Location(latitude: latitude, longitude: longitude)
    }

    var coordinateSnapshot: WorkoutCoordinateSnapshot {
        WorkoutCoordinateSnapshot(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracyMeters: horizontalAccuracyMeters
        )
    }

    var isValid: Bool {
        arrivalDate != .distantPast
            && arrivalDate != .distantFuture
            && CLLocationCoordinate2DIsValid(
                CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            )
            && horizontalAccuracyMeters >= 0
            && (departureDate.map { $0 > arrivalDate } ?? true)
    }
}

nonisolated struct MotionTransitDetection: Hashable, Sendable {
    let kind: MotionTransitKind
    let confidenceRawValue: Int
    let startTime: Date
    let endTime: Date
    let originLocation: Location
    let originPlaceID: UUID?
    let destinationLocation: Location
    let destinationPlaceID: UUID?
}

nonisolated enum AutomationCandidateStore {
    static func upsertVisit(
        _ visit: VisitDetectionSnapshot,
        in modelContext: ModelContext
    ) throws -> AutomationCandidate? {
        guard visit.isValid else { return nil }
        let candidates = try modelContext.fetch(
            FetchDescriptor<AutomationCandidate>()
        )
        let fingerprint = visitFingerprint(for: visit)
        let existing = candidates.first {
            $0.sourceFingerprint == fingerprint
        } ?? matchingOpenVisit(for: visit, in: candidates)

        if let existing {
            guard existing.status == .pending else { return existing }
            existing.sourceFingerprint = fingerprint
            existing.startTime = visit.arrivalDate
            existing.endTime = visit.departureDate
            existing.visitLocation = visit.location
            existing.visitHorizontalAccuracyMeters = visit
                .horizontalAccuracyMeters
            existing.updatedAt = .now
            return existing
        }

        let candidate = AutomationCandidate(
            sourceFingerprint: fingerprint,
            kind: .visit,
            startTime: visit.arrivalDate,
            endTime: visit.departureDate,
            visitLocation: visit.location,
            visitHorizontalAccuracyMeters: visit.horizontalAccuracyMeters
        )
        modelContext.insert(candidate)
        return candidate
    }

    static func upsertMotion(
        _ detection: MotionTransitDetection,
        in modelContext: ModelContext
    ) throws -> AutomationCandidate? {
        let fingerprint = motionFingerprint(for: detection)
        let descriptor = FetchDescriptor<AutomationCandidate>(
            predicate: #Predicate { candidate in
                candidate.sourceFingerprint == fingerprint
            }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            guard existing.status == .pending else { return existing }
            existing.startTime = detection.startTime
            existing.endTime = detection.endTime
            existing.timeZoneIdentifier = detection.originLocation
                .timeZoneIdentifier ?? existing.timeZoneIdentifier
            existing.motionKind = detection.kind
            existing.motionConfidenceRawValue = detection.confidenceRawValue
            if detection.originPlaceID != nil || existing.originPlaceID == nil {
                existing.originLocation = detection.originLocation
            }
            existing.originPlaceID = detection.originPlaceID
                ?? existing.originPlaceID
            if detection.destinationPlaceID != nil
                || existing.destinationPlaceID == nil {
                existing.destinationLocation = detection.destinationLocation
            }
            existing.destinationPlaceID = detection.destinationPlaceID
                ?? existing.destinationPlaceID
            existing.updatedAt = .now
            return existing
        }

        let zone = detection.originLocation.timeZoneIdentifier
            ?? TimeZone.current.identifier
        let candidate = AutomationCandidate(
            sourceFingerprint: fingerprint,
            kind: .transit,
            startTime: detection.startTime,
            endTime: detection.endTime,
            timeZoneIdentifier: zone,
            motionKind: detection.kind,
            motionConfidenceRawValue: detection.confidenceRawValue,
            originLocation: detection.originLocation,
            originPlaceID: detection.originPlaceID,
            destinationLocation: detection.destinationLocation,
            destinationPlaceID: detection.destinationPlaceID
        )
        modelContext.insert(candidate)
        return candidate
    }

    static func candidate(
        withID id: UUID,
        in modelContext: ModelContext
    ) throws -> AutomationCandidate? {
        let descriptor = FetchDescriptor<AutomationCandidate>(
            predicate: #Predicate { candidate in candidate.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    static func dismiss(
        _ candidate: AutomationCandidate,
        in modelContext: ModelContext
    ) throws {
        guard candidate.status == .pending else { return }
        let candidateID = candidate.id
        candidate.status = .dismissed
        candidate.updatedAt = .now
        do {
            try modelContext.delete(
                model: LogEntry.self,
                where: #Predicate {
                    $0.id == candidateID
                        || $0.automationCandidateID == candidateID
                }
            )
            try modelContext.save()
            NotificationCenter.default.post(
                name: .automationCandidatesDidChange,
                object: nil
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    static func dismiss(
        candidateID: UUID,
        in modelContext: ModelContext
    ) throws {
        guard let candidate = try candidate(
            withID: candidateID,
            in: modelContext
        ) else { return }
        try dismiss(candidate, in: modelContext)
    }

    @discardableResult
    static func acceptMaterializedTransit(
        candidateID: UUID,
        entryID: UUID,
        in modelContext: ModelContext
    ) throws -> UUID? {
        guard let candidate = try candidate(
            withID: candidateID,
            in: modelContext
        ), candidate.status == .pending,
           candidate.kind == .transit else {
            return nil
        }

        let requestedEntry = try modelContext.fetch(
            FetchDescriptor<LogEntry>(
                predicate: #Predicate { $0.id == entryID }
            )
        ).first
        let entry = try (
            requestedEntry ?? modelContext.fetch(
                FetchDescriptor<LogEntry>(
                    predicate: #Predicate {
                        $0.automationCandidateID == candidateID
                    }
                )
            ).first
        )
        guard let entry,
              entry.kind == .transit,
              entry.id == candidateID
                || entry.automationCandidateID == candidateID else {
            return nil
        }

        entry.automationCandidateID = candidateID
        entry.needsReview = false
        entry.entryKindReviewReason = nil
        entry.transitDetails?.fieldReviews = []
        markAccepted(candidate, entryID: entry.id)

        do {
            try modelContext.save()
            NotificationCenter.default.post(
                name: .automationCandidatesDidChange,
                object: nil
            )
            return entry.id
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    static func markAccepted(
        _ candidate: AutomationCandidate,
        entryID: UUID
    ) {
        candidate.status = .accepted
        candidate.acceptedEntryID = entryID
        candidate.provenanceRecordedAt = .now
        candidate.updatedAt = .now
    }

    nonisolated static func visitFingerprint(
        for visit: VisitDetectionSnapshot
    ) -> String {
        let minute = Int(visit.arrivalDate.timeIntervalSince1970 / 60)
        let latitude = Int((visit.latitude * 1_000).rounded())
        let longitude = Int((visit.longitude * 1_000).rounded())
        return "visit|\(minute)|\(latitude)|\(longitude)"
    }

    nonisolated static func motionFingerprint(
        for detection: MotionTransitDetection
    ) -> String {
        let start = Int(detection.startTime.timeIntervalSince1970.rounded())
        let end = Int(detection.endTime.timeIntervalSince1970.rounded())
        return "motion|\(detection.kind.rawValue)|\(start)|\(end)"
    }

    private static func matchingOpenVisit(
        for visit: VisitDetectionSnapshot,
        in candidates: [AutomationCandidate]
    ) -> AutomationCandidate? {
        let coordinate = CLLocation(
            latitude: visit.latitude,
            longitude: visit.longitude
        )
        return candidates.first { candidate in
            guard candidate.kind == .visit,
                  candidate.status == .pending,
                  candidate.endTime == nil,
                  abs(candidate.startTime.timeIntervalSince(visit.arrivalDate))
                    <= 10 * 60,
                  let location = candidate.visitLocation else {
                return false
            }
            let stored = CLLocation(
                latitude: location.latitude,
                longitude: location.longitude
            )
            let radius = max(
                100,
                visit.horizontalAccuracyMeters,
                candidate.visitHorizontalAccuracyMeters ?? 0
            )
            return coordinate.distance(from: stored) <= radius
        }
    }
}
