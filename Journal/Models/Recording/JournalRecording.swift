import Foundation
import SwiftData

nonisolated enum JournalRecordingStatus: String, Codable, Hashable, Sendable {
    case starting
    case awaitingForeground
    case recording
    case stopping
}

nonisolated enum JournalRecordingStartPath: String, Codable, Hashable, Sendable {
    case backgroundIntent
    case foregroundFallback
}

nonisolated enum JournalRecordingMode: String, Codable, Hashable, Sendable {
    case singleEntry
    case continuous
}

nonisolated enum RecordedMotionKind: String, Codable, Hashable, Sendable {
    case stationary
    case walking
    case running
    case cycling
    case automotive
    case unknown
}

nonisolated enum RecordedTransitMode: String, Codable, Hashable, Sendable {
    case walking
    case cycling
    case automotive
    case unknown

    var transitTypeName: String {
        switch self {
        case .walking: "Walk"
        case .cycling: "Bicycle"
        case .automotive: "Car"
        case .unknown: "Unknown"
        }
    }

    var activityDescription: String {
        switch self {
        case .walking: String(localized: "Walking")
        case .cycling: String(localized: "Cycling")
        case .automotive: String(localized: "In a vehicle")
        case .unknown: String(localized: "Recording")
        }
    }
}

nonisolated struct TrackedLocationPoint: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var horizontalAccuracy: Double
    var altitude: Double?
    var speed: Double?
    var course: Double?
}

nonisolated struct RecordedRoutePoint: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
}

nonisolated struct RecordedMotionObservation: Codable, Hashable, Sendable {
    var startTime: Date
    var endTime: Date
    var kind: RecordedMotionKind
    var confidenceRawValue: Int
}

nonisolated struct JournalRecordingPlaceRegion: Hashable, Sendable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double
    var isHome: Bool
}

nonisolated struct JournalRecordingVisitEvidence: Hashable, Sendable {
    var startTime: Date
    var endTime: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracyMeters: Double
    var placeID: UUID?
}

@Model
final class ActiveJournalRecording {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var lastUpdatedAt: Date
    var status: JournalRecordingStatus
    var startPath: JournalRecordingStartPath
    var mode: JournalRecordingMode = JournalRecordingMode.singleEntry
    var activityID: String?
    var approximateDistanceMeters: Double
    var currentMovement: RecordedTransitMode
    var points: [TrackedLocationPoint]
    var lastDiagnostic: String?

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        endedAt: Date? = nil,
        lastUpdatedAt: Date = .now,
        status: JournalRecordingStatus = .starting,
        startPath: JournalRecordingStartPath,
        mode: JournalRecordingMode = .singleEntry,
        activityID: String? = nil,
        approximateDistanceMeters: Double = 0,
        currentMovement: RecordedTransitMode = .unknown,
        points: [TrackedLocationPoint] = [],
        lastDiagnostic: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.status = status
        self.startPath = startPath
        self.mode = mode
        self.activityID = activityID
        self.approximateDistanceMeters = approximateDistanceMeters
        self.currentMovement = currentMovement
        self.points = points
        self.lastDiagnostic = lastDiagnostic
    }
}
