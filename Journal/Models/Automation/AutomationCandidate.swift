import Foundation
import SwiftData

nonisolated enum AutomationCandidateKind: String, Codable, Hashable, Sendable {
    case visit
    case transit
}

nonisolated enum AutomationCandidateStatus: String, Codable, Hashable, Sendable {
    case pending
    case accepted
    case dismissed
}

nonisolated enum MotionTransitKind: String, Codable, Hashable, Sendable {
    case walk
    case bicycle
    case automotive

    var transitTypeName: String {
        switch self {
        case .walk: "Walk"
        case .bicycle: "Bicycle"
        case .automotive: "Car"
        }
    }
}

@Model
final class AutomationCandidate {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var sourceFingerprint: String
    var kind: AutomationCandidateKind
    var status: AutomationCandidateStatus
    var createdAt: Date
    var updatedAt: Date
    var startTime: Date
    var endTime: Date?
    var timeZoneIdentifier: String

    var visitLocation: Location?
    var visitHorizontalAccuracyMeters: Double?
    var visitPlaceID: UUID?

    var motionKind: MotionTransitKind?
    var motionConfidenceRawValue: Int?
    var originLocation: Location?
    var originPlaceID: UUID?
    var destinationLocation: Location?
    var destinationPlaceID: UUID?

    var acceptedEntryID: UUID?
    var provenanceRecordedAt: Date?

    init(
        id: UUID = UUID(),
        sourceFingerprint: String,
        kind: AutomationCandidateKind,
        status: AutomationCandidateStatus = .pending,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        startTime: Date,
        endTime: Date? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        visitLocation: Location? = nil,
        visitHorizontalAccuracyMeters: Double? = nil,
        visitPlaceID: UUID? = nil,
        motionKind: MotionTransitKind? = nil,
        motionConfidenceRawValue: Int? = nil,
        originLocation: Location? = nil,
        originPlaceID: UUID? = nil,
        destinationLocation: Location? = nil,
        destinationPlaceID: UUID? = nil,
        acceptedEntryID: UUID? = nil,
        provenanceRecordedAt: Date? = nil
    ) {
        self.id = id
        self.sourceFingerprint = sourceFingerprint
        self.kind = kind
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startTime = startTime
        self.endTime = endTime
        self.timeZoneIdentifier = timeZoneIdentifier
        self.visitLocation = visitLocation
        self.visitHorizontalAccuracyMeters = visitHorizontalAccuracyMeters
        self.visitPlaceID = visitPlaceID
        self.motionKind = motionKind
        self.motionConfidenceRawValue = motionConfidenceRawValue
        self.originLocation = originLocation
        self.originPlaceID = originPlaceID
        self.destinationLocation = destinationLocation
        self.destinationPlaceID = destinationPlaceID
        self.acceptedEntryID = acceptedEntryID
        self.provenanceRecordedAt = provenanceRecordedAt
    }
}

nonisolated struct AutomationCandidateSnapshot: Hashable, Identifiable, Sendable {
    let id: UUID
    let kind: AutomationCandidateKind
    let startTime: Date
    let endTime: Date
    let timeZoneIdentifier: String
    let endTimeZoneIdentifier: String
    let visitLocation: Location?
    let visitPlaceID: UUID?
    let visitName: String
    let motionKind: MotionTransitKind?
    let originLocation: Location?
    let originPlaceID: UUID?
    let originName: String
    let destinationLocation: Location?
    let destinationPlaceID: UUID?
    let destinationName: String

    @MainActor
    init?(
        _ candidate: AutomationCandidate,
        placesByID: [UUID: Place] = [:]
    ) {
        guard candidate.status == .pending,
              let endTime = candidate.endTime,
              endTime > candidate.startTime else {
            return nil
        }
        id = candidate.id
        kind = candidate.kind
        startTime = candidate.startTime
        self.endTime = endTime
        let startZone = switch candidate.kind {
        case .visit:
            candidate.visitPlaceID.flatMap {
                placesByID[$0]?.location.timeZoneIdentifier
            } ?? candidate.visitLocation?.timeZoneIdentifier
                ?? candidate.timeZoneIdentifier
        case .transit:
            candidate.originPlaceID.flatMap {
                placesByID[$0]?.location.timeZoneIdentifier
            } ?? candidate.originLocation?.timeZoneIdentifier
                ?? candidate.timeZoneIdentifier
        }
        timeZoneIdentifier = startZone
        endTimeZoneIdentifier = candidate.kind == .transit
            ? candidate.destinationPlaceID.flatMap {
                placesByID[$0]?.location.timeZoneIdentifier
            } ?? candidate.destinationLocation?.timeZoneIdentifier
                ?? startZone
            : startZone
        visitLocation = candidate.visitLocation
        visitPlaceID = candidate.visitPlaceID
        visitName = candidate.visitPlaceID.flatMap { placesByID[$0]?.name }
            ?? candidate.visitLocation?.preferredName
            ?? String(localized: "Detected place")
        motionKind = candidate.motionKind
        originLocation = candidate.originLocation
        originPlaceID = candidate.originPlaceID
        originName = candidate.originPlaceID.flatMap { placesByID[$0]?.name }
            ?? candidate.originLocation?.preferredName
            ?? String(localized: "Detected origin")
        destinationLocation = candidate.destinationLocation
        destinationPlaceID = candidate.destinationPlaceID
        destinationName = candidate.destinationPlaceID.flatMap {
            placesByID[$0]?.name
        } ?? candidate.destinationLocation?.preferredName
            ?? String(localized: "Detected destination")
    }

    var day: TimelineDayKey {
        TimelineDayKey(
            date: startTime,
            timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current
        )
    }
}
