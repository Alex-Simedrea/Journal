//
//  Entry.swift
//  Journal
//
//  Created by Alexandru Simedrea on 11/07/2026.
//

import Foundation
import SwiftData

enum LogKind: String, Codable, Hashable, Sendable {
    case transit
    case placeVisit
    case workout
    case wakeUp
}

enum TimeConfidence: String, Codable, Hashable, Sendable {
    case explicit
    case inferredFromHistory
    case inferredNearOrigin
    case inferredNearDestination
    case unresolved
    case manualOverride
}

@Model
final class LogEntry {
    @Attribute(.unique) var id: UUID
    var kind: LogKind
    var createdAt: Date
    var startTime: Date?
    var endTime: Date?
    var startTimeZoneIdentifier: String
    var endTimeZoneIdentifier: String
    var creationTimeZoneIdentifier: String
    var timeConfidence: TimeConfidence
    var rawInputString: String?
    var modelInstructions: String?
    var modelPrompt: String?
    var modelToolTranscript: String?
    var modelResponse: String?
    var needsReview: Bool
    var entryKindReviewReason: String?
    var photoReferences: [PhotoReference] = []
    var weather: EntryWeather?
    var endWeather: EntryWeather?
    var wakeUpSourceSampleUUID: UUID?
    var sleepDurationSeconds: Double?

    @Relationship(deleteRule: .cascade) var transitDetails: TransitDetails?
    @Relationship(deleteRule: .cascade) var placeVisitDetails: PlaceVisitDetails?
    @Relationship(deleteRule: .cascade) var workoutDetails: WorkoutDetails?

    @Relationship(inverse: \Person.entries) var people: [Person] = []

    init(
        id: UUID,
        kind: LogKind,
        createdAt: Date,
        startTime: Date? = nil,
        endTime: Date? = nil,
        startTimeZoneIdentifier: String? = nil,
        endTimeZoneIdentifier: String? = nil,
        creationTimeZoneIdentifier: String = TimeZone.current.identifier,
        timeConfidence: TimeConfidence = .unresolved,
        rawInputString: String? = nil,
        modelInstructions: String? = nil,
        modelPrompt: String? = nil,
        modelToolTranscript: String? = nil,
        modelResponse: String? = nil,
        photoReferences: [PhotoReference] = [],
        weather: EntryWeather? = nil,
        endWeather: EntryWeather? = nil,
        wakeUpSourceSampleUUID: UUID? = nil,
        sleepDurationSeconds: Double? = nil,
        entryKindReviewReason: String? = nil,
        needsReview: Bool
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.startTime = startTime
        self.endTime = endTime
        self.startTimeZoneIdentifier = startTimeZoneIdentifier
            ?? creationTimeZoneIdentifier
        self.endTimeZoneIdentifier = endTimeZoneIdentifier
            ?? creationTimeZoneIdentifier
        self.creationTimeZoneIdentifier = creationTimeZoneIdentifier
        self.timeConfidence = timeConfidence
        self.rawInputString = rawInputString
        self.modelInstructions = modelInstructions
        self.modelPrompt = modelPrompt
        self.modelToolTranscript = modelToolTranscript
        self.modelResponse = modelResponse
        self.photoReferences = photoReferences
        self.weather = weather
        self.endWeather = endWeather
        self.wakeUpSourceSampleUUID = wakeUpSourceSampleUUID
        self.sleepDurationSeconds = sleepDurationSeconds
        self.entryKindReviewReason = entryKindReviewReason
        self.needsReview = needsReview
    }

    convenience init(
        kind: LogKind,
        startTime: Date? = nil,
        endTime: Date? = nil,
        startTimeZoneIdentifier: String? = nil,
        endTimeZoneIdentifier: String? = nil,
        creationTimeZoneIdentifier: String = TimeZone.current.identifier,
        timeConfidence: TimeConfidence = .unresolved,
        rawInputString: String? = nil,
        modelInstructions: String? = nil,
        modelPrompt: String? = nil,
        modelToolTranscript: String? = nil,
        modelResponse: String? = nil,
        photoReferences: [PhotoReference] = [],
        weather: EntryWeather? = nil,
        endWeather: EntryWeather? = nil,
        wakeUpSourceSampleUUID: UUID? = nil,
        sleepDurationSeconds: Double? = nil,
        entryKindReviewReason: String? = nil,
        needsReview: Bool
    ) {
        self.init(
            id: UUID(),
            kind: kind,
            createdAt: .now,
            startTime: startTime,
            endTime: endTime,
            startTimeZoneIdentifier: startTimeZoneIdentifier,
            endTimeZoneIdentifier: endTimeZoneIdentifier,
            creationTimeZoneIdentifier: creationTimeZoneIdentifier,
            timeConfidence: timeConfidence,
            rawInputString: rawInputString,
            modelInstructions: modelInstructions,
            modelPrompt: modelPrompt,
            modelToolTranscript: modelToolTranscript,
            modelResponse: modelResponse,
            photoReferences: photoReferences,
            weather: weather,
            endWeather: endWeather,
            wakeUpSourceSampleUUID: wakeUpSourceSampleUUID,
            sleepDurationSeconds: sleepDurationSeconds,
            entryKindReviewReason: entryKindReviewReason,
            needsReview: needsReview
        )
    }
}
