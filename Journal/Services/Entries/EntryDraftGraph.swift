import Foundation
import SwiftData

/// Review models are a detached graph. Never attach a saved model to them:
/// inverse relationship maintenance can insert the draft before confirmation.
nonisolated enum EntryDraftGraph {
    static func place(_ source: Place?) -> Place? {
        guard let source else { return nil }
        return Place(
            id: source.id, name: source.name, aliases: source.aliases,
            location: source.location, systemImage: source.systemImage,
            createdAt: source.createdAt, accuracyRadiusMeters: source.accuracyRadiusMeters
        )
    }

    static func person(_ source: Person) -> Person {
        Person(
            id: source.id, name: source.name, aliases: source.aliases,
            contactIdentifier: source.contactIdentifier,
            firstMetAt: source.firstMetAt, lastMetAt: source.lastMetAt
        )
    }

    /// Make a fresh commit graph so a failed save/rollback cannot invalidate the
    /// still-visible review draft. Resolve saved relationships in the destination
    /// context; deleted choices retain their historical location, never resurrect
    /// a deleted saved place or insert a duplicate unique-ID model.
    @MainActor
    static func materialize(
        _ draft: LogEntry,
        selectedPeopleIDs: Set<UUID>,
        in context: ModelContext
    ) throws -> LogEntry {
        guard draft.kind == .transit || draft.kind == .placeVisit else {
            throw DraftError.unsupportedKind
        }
        let places = Dictionary(try context.fetch(FetchDescriptor<Place>()).map {
            ($0.id, $0)
        }, uniquingKeysWith: { first, _ in first })
        func savedPlace(_ place: Place?) -> Place? {
            place.flatMap { places[$0.id] }
        }
        let entry = LogEntry(
            id: draft.id, kind: draft.kind, createdAt: draft.createdAt,
            startTime: draft.startTime, endTime: draft.endTime,
            startTimeZoneIdentifier: draft.startTimeZoneIdentifier,
            endTimeZoneIdentifier: draft.endTimeZoneIdentifier,
            creationTimeZoneIdentifier: draft.creationTimeZoneIdentifier,
            timeConfidence: draft.timeConfidence, rawInputString: draft.rawInputString,
            automationCandidateID: draft.automationCandidateID,
            journalRecordingID: draft.journalRecordingID,
            photoReferences: draft.photoReferences, weather: draft.weather,
            endWeather: draft.endWeather, dayWeatherRecords: draft.dayWeatherRecords,
            wakeUpSourceSampleUUID: draft.wakeUpSourceSampleUUID,
            sleepDurationSeconds: draft.sleepDurationSeconds,
            entryKindReviewReason: draft.entryKindReviewReason,
            linkedPreviousEntryID: draft.linkedPreviousEntryID,
            linkedNextEntryID: draft.linkedNextEntryID,
            suppressedPreviousEntryID: draft.suppressedPreviousEntryID,
            suppressedNextEntryID: draft.suppressedNextEntryID,
            needsReview: draft.needsReview
        )
        if let details = draft.transitDetails {
            entry.transitDetails = TransitDetails(
                type: details.type,
                sourceOrganizationName: details.sourceOrganizationName,
                sourceServiceIdentifier: details.sourceServiceIdentifier,
                originPlace: savedPlace(details.originPlace),
                originLocation: details.originLocation, originRawText: details.originRawText,
                destinationPlace: savedPlace(details.destinationPlace),
                destinationLocation: details.destinationLocation,
                destinationRawText: details.destinationRawText,
                durationSource: details.durationSource, distanceMeters: details.distanceMeters,
                recordedRoute: details.recordedRoute, recordedMotion: details.recordedMotion,
                recordedTransitMode: details.recordedTransitMode,
                originCandidates: details.originCandidates,
                destinationCandidates: details.destinationCandidates,
                unresolvedPeople: details.unresolvedPeople, fieldReviews: details.fieldReviews
            )
        }
        if let details = draft.placeVisitDetails {
            entry.placeVisitDetails = PlaceVisitDetails(
                description: details.description, place: savedPlace(details.place),
                location: details.location, placeRawText: details.placeRawText,
                candidates: details.candidates, unresolvedPeople: details.unresolvedPeople,
                fieldReviews: details.fieldReviews
            )
        }
        entry.people = try context.fetch(FetchDescriptor<Person>()).filter {
            selectedPeopleIDs.contains($0.id)
        }
        return entry
    }
    private enum DraftError: LocalizedError {
        case unsupportedKind
        var errorDescription: String? { "This entry type cannot be saved as a review draft." }
    }

}
