//
//  PlaceVisitEntryStore.swift
//  Journal
//

import Foundation
import SwiftData

enum PlaceVisitEntryStore {
    static func insert(
        draft: ResolvedPlaceVisitDraft,
        rawInput: String?,
        modelExchange: EntryModelExchange? = nil,
        in modelContext: ModelContext
    ) throws -> LogEntry {
        let location = draft.location?.withFallbackDisplayName(
            draft.place?.name
        )
        let details = PlaceVisitDetails(
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

        modelContext.insert(entry)
        try modelContext.save()
        return entry
    }
}
