//
//  TransitEntryStore.swift
//  Journal
//

import Foundation
import SwiftData

@MainActor
enum TransitEntryStore {
    static func insert(
        draft: ResolvedTransitDraft,
        rawInput: String?,
        sourceOrganizationName: String? = nil,
        sourceServiceIdentifier: String? = nil,
        in modelContext: ModelContext
    ) throws -> LogEntry {
        let entry = makeEntry(
            draft: draft,
            rawInput: rawInput,
            sourceOrganizationName: sourceOrganizationName,
            sourceServiceIdentifier: sourceServiceIdentifier
        )
        try insert(entry, in: modelContext)
        return entry
    }

    nonisolated static func makeEntry(
        draft: ResolvedTransitDraft,
        rawInput: String?,
        sourceOrganizationName: String? = nil,
        sourceServiceIdentifier: String? = nil,
        detachedRelationships: Bool = false
    ) -> LogEntry {
        let originLocation = draft.originLocation?
            .withFallbackDisplayName(draft.originPlace?.name)
        let destinationLocation = draft.destinationLocation?
            .withFallbackDisplayName(draft.destinationPlace?.name)
        let details = TransitDetails(
            type: draft.transitType,
            sourceOrganizationName: sourceOrganizationName,
            sourceServiceIdentifier: sourceServiceIdentifier,
            originPlace: detachedRelationships ? EntryDraftGraph.place(draft.originPlace) : draft.originPlace,
            originLocation: originLocation,
            originRawText: draft.originRawText,
            destinationPlace: detachedRelationships ? EntryDraftGraph.place(draft.destinationPlace) : draft.destinationPlace,
            destinationLocation: destinationLocation,
            destinationRawText: draft.destinationRawText,
            durationSource: draft.durationSource,
            originCandidates: draft.originCandidates,
            destinationCandidates: draft.destinationCandidates,
            unresolvedPeople: draft.unresolvedPeople,
            fieldReviews: draft.fieldReviews
        )
        let creationTimeZoneIdentifier = TimeZone.current.identifier
        let startTimeZoneIdentifier = originLocation?.timeZoneIdentifier
            ?? draft.originPlace?.location.timeZoneIdentifier
            ?? draft.originCandidates.first?.timeZoneIdentifier
            ?? creationTimeZoneIdentifier
        let endTimeZoneIdentifier = destinationLocation?.timeZoneIdentifier
            ?? draft.destinationPlace?.location.timeZoneIdentifier
            ?? draft.destinationCandidates.first?.timeZoneIdentifier
            ?? creationTimeZoneIdentifier
        let entry = LogEntry(
            kind: .transit,
            startTime: draft.startTime,
            endTime: draft.endTime,
            startTimeZoneIdentifier: startTimeZoneIdentifier,
            endTimeZoneIdentifier: endTimeZoneIdentifier,
            creationTimeZoneIdentifier: creationTimeZoneIdentifier,
            timeConfidence: draft.timeConfidence,
            rawInputString: rawInput,
            entryKindReviewReason: draft.entryKindReviewReason,
            needsReview: draft.needsReview
        )
        entry.transitDetails = details
        entry.people = detachedRelationships ? draft.people.map(EntryDraftGraph.person) : draft.people

        return entry
    }

    static func insert(
        _ entry: LogEntry,
        refreshDistance: Bool = true,
        in modelContext: ModelContext
    ) throws {
        do {
            modelContext.insert(entry)
            _ = try EntryLinkingService.reconcile(in: modelContext)
            try JournalPersistence.save(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
        if refreshDistance {
            TransitDistanceService.refreshInBackground(entry, in: modelContext)
        }
    }
}
