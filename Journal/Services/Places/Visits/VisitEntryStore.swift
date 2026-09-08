//
//  PlaceVisitEntryStore.swift
//  Journal
//

import Foundation
import SwiftData

/// Pure model construction/insertion on the caller's context; runs on
/// whichever executor owns that context.
nonisolated enum PlaceVisitEntryStore {
    static func insert(
        draft: ResolvedPlaceVisitDraft,
        rawInput: String?,
        in modelContext: ModelContext
    ) throws -> LogEntry {
        let entry = makeEntry(
            draft: draft,
            rawInput: rawInput
        )
        try insert(entry, in: modelContext)
        return entry
    }

    static func makeEntry(
        draft: ResolvedPlaceVisitDraft,
        rawInput: String?,
        detachedRelationships: Bool = false
    ) -> LogEntry {
        let location = draft.location?.withFallbackDisplayName(
            draft.place?.name
        )
        let details = PlaceVisitDetails(
            description: draft.description,
            place: detachedRelationships ? EntryDraftGraph.place(draft.place) : draft.place,
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
            entryKindReviewReason: draft.entryKindReviewReason,
            needsReview: draft.needsReview
        )
        entry.placeVisitDetails = details
        entry.people = detachedRelationships ? draft.people.map(EntryDraftGraph.person) : draft.people
        return entry
    }

    static func insert(_ entry: LogEntry, in modelContext: ModelContext) throws {
        do {
            modelContext.insert(entry)
            _ = try EntryLinkingService.reconcile(in: modelContext)
            try JournalPersistence.save(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
