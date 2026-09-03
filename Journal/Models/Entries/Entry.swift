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
    var automationCandidateID: UUID?
    var journalRecordingID: UUID?
    var needsReview: Bool
    var entryKindReviewReason: String?
    // SwiftData expands Codable structs into traversable schema key paths.
    // Observation can then try to materialize paths such as
    // `weather.condition`, which traps when the path crosses an optional
    // Codable value. Store these values as opaque JSON blobs and expose the
    // same typed API through computed properties instead.
    @Attribute(originalName: "photoReferences")
    private var photoReferencesData: Data?
    @Attribute(originalName: "weather")
    private var weatherData: Data?
    @Attribute(originalName: "endWeather")
    private var endWeatherData: Data?
    @Attribute(originalName: "dayWeatherRecords")
    private var dayWeatherRecordsData: Data?

    var photoReferences: [PhotoReference] {
        get {
            PersistedJSON.decode(
                [PhotoReference].self,
                from: photoReferencesData
            ) ?? []
        }
        set { photoReferencesData = PersistedJSON.encode(newValue) }
    }

    var weather: EntryWeather? {
        get { PersistedJSON.decode(EntryWeather.self, from: weatherData) }
        set { weatherData = newValue.flatMap(PersistedJSON.encode) }
    }

    var endWeather: EntryWeather? {
        get { PersistedJSON.decode(EntryWeather.self, from: endWeatherData) }
        set { endWeatherData = newValue.flatMap(PersistedJSON.encode) }
    }

    var dayWeatherRecords: [PersistedDayWeather] {
        get {
            PersistedJSON.decode(
                [PersistedDayWeather].self,
                from: dayWeatherRecordsData
            ) ?? []
        }
        set { dayWeatherRecordsData = PersistedJSON.encode(newValue) }
    }
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
        automationCandidateID: UUID? = nil,
        journalRecordingID: UUID? = nil,
        photoReferences: [PhotoReference] = [],
        weather: EntryWeather? = nil,
        endWeather: EntryWeather? = nil,
        dayWeatherRecords: [PersistedDayWeather] = [],
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
        self.automationCandidateID = automationCandidateID
        self.journalRecordingID = journalRecordingID
        self.photoReferencesData = PersistedJSON.encode(photoReferences)
        self.weatherData = weather.flatMap(PersistedJSON.encode)
        self.endWeatherData = endWeather.flatMap(PersistedJSON.encode)
        self.dayWeatherRecordsData = PersistedJSON.encode(dayWeatherRecords)
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
        automationCandidateID: UUID? = nil,
        journalRecordingID: UUID? = nil,
        photoReferences: [PhotoReference] = [],
        weather: EntryWeather? = nil,
        endWeather: EntryWeather? = nil,
        dayWeatherRecords: [PersistedDayWeather] = [],
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
            automationCandidateID: automationCandidateID,
            journalRecordingID: journalRecordingID,
            photoReferences: photoReferences,
            weather: weather,
            endWeather: endWeather,
            dayWeatherRecords: dayWeatherRecords,
            wakeUpSourceSampleUUID: wakeUpSourceSampleUUID,
            sleepDurationSeconds: sleepDurationSeconds,
            entryKindReviewReason: entryKindReviewReason,
            needsReview: needsReview
        )
    }
}
