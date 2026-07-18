//
//  TransitEntryStore.swift
//  Journal
//

import Foundation
import SwiftData

enum TransitEntryStore {
    static func insert(
        draft: ResolvedTransitDraft,
        rawInput: String?,
        modelExchange: EntryModelExchange? = nil,
        sourceOrganizationName: String? = nil,
        sourceServiceIdentifier: String? = nil,
        in modelContext: ModelContext
    ) throws -> LogEntry {
        let details = TransitDetails(
            type: draft.transitType,
            sourceOrganizationName: sourceOrganizationName,
            sourceServiceIdentifier: sourceServiceIdentifier,
            originPlace: draft.originPlace,
            originRawText: draft.originRawText,
            destinationPlace: draft.destinationPlace,
            destinationRawText: draft.destinationRawText,
            durationSource: draft.durationSource,
            originCandidates: draft.originCandidates,
            destinationCandidates: draft.destinationCandidates,
            unresolvedPeople: draft.unresolvedPeople,
            fieldReviews: draft.fieldReviews
        )
        let creationTimeZoneIdentifier = TimeZone.current.identifier
        let startTimeZoneIdentifier = draft.originPlace?.location.timeZoneIdentifier
            ?? draft.originCandidates.first?.timeZoneIdentifier
            ?? creationTimeZoneIdentifier
        let endTimeZoneIdentifier = draft.destinationPlace?.location.timeZoneIdentifier
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
            modelInstructions: modelExchange?.instructions,
            modelPrompt: modelExchange?.prompt,
            modelToolTranscript: modelExchange?.toolTranscript,
            modelResponse: modelExchange?.response,
            entryKindReviewReason: draft.entryKindReviewReason,
            needsReview: draft.needsReview
        )
        entry.transitDetails = details
        entry.people = draft.people

        modelContext.insert(entry)
        try modelContext.save()
        return entry
    }
}
