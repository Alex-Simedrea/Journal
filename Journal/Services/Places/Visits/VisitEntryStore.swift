//
//  PlaceVisitEntryStore.swift
//  Journal
//

import Foundation
import SwiftData

nonisolated enum PlaceVisitEntryStore {
    static func insert(
        draft: ResolvedPlaceVisitDraft,
        rawInput: String?,
        modelExchange: EntryModelExchange? = nil,
        in modelContext: ModelContext
    ) throws -> LogEntry {
        let entry = makeEntry(
            draft: draft,
            rawInput: rawInput,
            modelExchange: modelExchange
        )
        try insert(entry, in: modelContext)
        return entry
    }

    static func makeEntry(
        draft: ResolvedPlaceVisitDraft,
        rawInput: String?,
        modelExchange: EntryModelExchange? = nil
    ) -> LogEntry {
        let location = draft.location?.withFallbackDisplayName(
            draft.place?.name
        )
        let details = PlaceVisitDetails(
            description: draft.description,
            place: draft.place,
            location: location,
            placeRawText: draft.placeRawText,
            candidates: draft.candidates,
            unresolvedPeople: draft.unresolvedPeople,
            fieldReviews: draft.fieldReviews
        )
        let creationZone = TimeZone.current.identifier
        let visitZone = location?.timeZoneIdentifier
            ?? draft.place?.location.timeZoneIdentifier
            ?? draft.candidates.first?.timeZoneIdentifier
            ?? creationZone
        let entry = LogEntry(
            kind: .placeVisit,
            startTime: draft.startTime,
            endTime: draft.endTime,
            startTimeZoneIdentifier: visitZone,
            endTimeZoneIdentifier: visitZone,
            creationTimeZoneIdentifier: creationZone,
            timeConfidence: draft.timeConfidence,
            rawInputString: rawInput,
            modelInstructions: modelExchange?.instructions,
            modelPrompt: modelExchange?.prompt,
            modelToolTranscript: modelExchange?.toolTranscript,
            modelResponse: modelExchange?.response,
            entryKindReviewReason: draft.entryKindReviewReason,
            needsReview: draft.needsReview
        )
        entry.placeVisitDetails = details
        entry.people = draft.people
        return entry
    }

    static func insert(_ entry: LogEntry, in modelContext: ModelContext) throws {
        modelContext.insert(entry)
        try modelContext.save()
    }
}
