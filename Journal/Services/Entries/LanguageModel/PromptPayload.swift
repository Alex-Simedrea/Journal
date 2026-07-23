import AnyLanguageModel
import CoreLocation
import Foundation
import MapKit

struct EntryPromptPayload: Encodable {
    let currentLocationContext: EntryCurrentLocationContext
    let selectedDayHistory: SelectedDayHistoryPromptContext
    let savedPlaces: [SavedPlacePromptContext]
    let people: [PersonPromptContext]
    let transitTypes: [TransitTypePromptContext]
    let userEntryText: String
}

struct SelectedDayHistoryPromptContext: Encodable {
    let entries: [SelectedDayEntryPromptContext]
}

struct SelectedDayEntryPromptContext: Encodable {
    let entryKey: String
    let relativeDay: String
    let entryKind: String
    let entryKindNeedsReview: Bool
    let reviewedFields: [String]
    let startTimeISO8601: String?
    let endTimeISO8601: String?
    let startTimeZoneIdentifier: String
    let endTimeZoneIdentifier: String
    let timeConfidence: String
    let transit: SelectedDayTransitPromptContext?
    let placeVisit: SelectedDayVisitPromptContext?
    let workout: SelectedDayWorkoutPromptContext?
    let wakeUp: SelectedDayWakeUpPromptContext?
    let peopleKeys: [String]
}

struct SelectedDayTransitPromptContext: Encodable {
    let canonicalTransitType: String
    let origin: SelectedDayLocationPromptContext?
    let destination: SelectedDayLocationPromptContext?
}

struct SelectedDayVisitPromptContext: Encodable {
    let location: SelectedDayLocationPromptContext?
}

struct SelectedDayWorkoutPromptContext: Encodable {
    let activityName: String
    let movementKind: String
    let location: SelectedDayLocationPromptContext?
    let origin: SelectedDayLocationPromptContext?
    let destination: SelectedDayLocationPromptContext?
    let distanceKilometers: Double?
}

struct SelectedDayWakeUpPromptContext: Encodable {
    let sleepDurationMinutes: Double?
}

struct SelectedDayLocationPromptContext: Encodable {
    let locationKey: String
    let savedPlaceKey: String?
    let displayName: String?
    let compactAddress: String?
    let fullAddress: String?
    let timeZoneIdentifier: String?
}

enum EntryDatePromptContext: Encodable {
    case today(timestampISO8601: String, timeZoneIdentifier: String)
    case selectedDate(localDate: String, timeZoneIdentifier: String)

    private enum CodingKeys: String, CodingKey {
        case mode
        case entryTimestampISO8601
        case entryLocalDate
        case timeZoneIdentifier
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .today(let timestampISO8601, let timeZoneIdentifier):
            try container.encode("today", forKey: .mode)
            try container.encode(
                timestampISO8601,
                forKey: .entryTimestampISO8601
            )
            try container.encode(
                timeZoneIdentifier,
                forKey: .timeZoneIdentifier
            )
        case .selectedDate(let localDate, let timeZoneIdentifier):
            try container.encode("selectedDate", forKey: .mode)
            try container.encode(localDate, forKey: .entryLocalDate)
            try container.encode(
                timeZoneIdentifier,
                forKey: .timeZoneIdentifier
            )
        }
    }
}

struct EntryCurrentLocationContext: Encodable {
    let currentAddress: String?
}

struct SavedPlacePromptContext: Encodable {
    let locationKey: String
    let name: String
    let aliases: [String]
    let address: String?
    let timeZoneIdentifier: String?
    let distanceFromCurrentKilometers: Double
    let accuracyRadiusKilometers: Double
    let effectiveProximityRadiusKilometers: Double
    let isCurrentLocationInsideProximityRadius: Bool
    let lastVisitedAtISO8601: String?
    let visitCount: Int
}

struct PersonPromptContext: Encodable {
    let personKey: String
    let name: String
    let aliases: [String]
}

struct TransitTypePromptContext: Encodable {
    let canonicalName: String
    let aliases: [String]
    let routingMode: String
}
