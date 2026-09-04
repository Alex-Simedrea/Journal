import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AutomationCandidateReviewModel {
    private(set) var isSaving = false
    var errorMessage: String?

    func makeDraft(
        candidate: AutomationCandidate,
        places: [Place],
        materializedEntry: LogEntry? = nil
    ) -> LogEntry? {
        guard let draft = AutomationCandidateEntryFactory.makeEntry(
            for: candidate,
            places: places,
            needsReview: false
        ) else { return nil }
        guard let materializedEntry else { return draft }

        draft.photoReferences = materializedEntry.photoReferences
        draft.weather = materializedEntry.weather
        draft.endWeather = materializedEntry.endWeather
        draft.dayWeatherRecords = materializedEntry.dayWeatherRecords
        draft.linkedPreviousEntryID = materializedEntry.linkedPreviousEntryID
        draft.linkedNextEntryID = materializedEntry.linkedNextEntryID
        draft.suppressedPreviousEntryID = materializedEntry.suppressedPreviousEntryID
        draft.suppressedNextEntryID = materializedEntry.suppressedNextEntryID
        draft.transitDetails?.distanceMeters = materializedEntry
            .transitDetails?.distanceMeters
        return draft
    }

    func commit(
        _ entry: LogEntry,
        selectedPeopleIDs: Set<UUID>,
        candidate: AutomationCandidate,
        in modelContext: ModelContext,
        performEnrichment: Bool = true
    ) async -> Bool {
        guard candidate.status == .pending else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let selectedPeople = try modelContext.fetch(
                FetchDescriptor<Person>()
            ).filter { selectedPeopleIDs.contains($0.id) }
            let storedEntry = try materializedEntry(
                for: candidate,
                in: modelContext
            )
            let acceptedEntry: LogEntry
            if let storedEntry {
                try apply(
                    entry,
                    selectedPeople: selectedPeople,
                    to: storedEntry,
                    in: modelContext
                )
                acceptedEntry = storedEntry
            } else {
                entry.id = candidate.id
                entry.people = selectedPeople
                modelContext.insert(entry)
                acceptedEntry = entry
            }
            AutomationCandidateStore.markAccepted(
                candidate,
                entryID: acceptedEntry.id
            )
            try EntryLinkingService.finalizeDeclaredLinks(
                for: acceptedEntry,
                in: modelContext
            )
            _ = try EntryLinkingService.reconcile(in: modelContext)
            try modelContext.save()
            guard performEnrichment else { return true }
            let acceptedEntryID = acceptedEntry.id
            let acceptedKind = acceptedEntry.kind
            let enrichmentContext = ModelContext(modelContext.container)
            enrichmentContext.autosaveEnabled = false
            _ = try? await EntryWeatherService.populate(
                entryID: acceptedEntryID,
                in: enrichmentContext
            )
            if acceptedKind == .transit {
                await TransitDistanceService.populate(
                    entryID: acceptedEntryID,
                    in: enrichmentContext
                )
            }
            try? await PhotoAutoLinkService.synchronize(
                in: enrichmentContext
            )
            return true
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func materializedEntry(
        for candidate: AutomationCandidate,
        in modelContext: ModelContext
    ) throws -> LogEntry? {
        let id = candidate.id
        let canonicalEntry = try modelContext.fetch(
            FetchDescriptor<LogEntry>(
                predicate: #Predicate { $0.id == id }
            )
        ).first
        if let canonicalEntry { return canonicalEntry }

        return try modelContext.fetch(
            FetchDescriptor<LogEntry>(
                predicate: #Predicate {
                    $0.automationCandidateID == id
                }
            )
        ).first
    }

    private func apply(
        _ draft: LogEntry,
        selectedPeople: [Person],
        to entry: LogEntry,
        in modelContext: ModelContext
    ) throws {
        guard draft.kind == entry.kind else {
            throw AutomationCandidateReviewError.kindChanged
        }

        entry.kind = draft.kind
        entry.startTime = draft.startTime
        entry.endTime = draft.endTime
        entry.startTimeZoneIdentifier = draft.startTimeZoneIdentifier
        entry.endTimeZoneIdentifier = draft.endTimeZoneIdentifier
        entry.timeConfidence = draft.timeConfidence
        entry.rawInputString = draft.rawInputString
        entry.automationCandidateID = draft.automationCandidateID
        entry.needsReview = draft.needsReview
        entry.entryKindReviewReason = draft.entryKindReviewReason
        entry.linkedPreviousEntryID = draft.linkedPreviousEntryID
        entry.linkedNextEntryID = draft.linkedNextEntryID
        entry.suppressedPreviousEntryID = draft.suppressedPreviousEntryID
        entry.suppressedNextEntryID = draft.suppressedNextEntryID
        entry.photoReferences = draft.photoReferences
        entry.weather = draft.weather
        entry.endWeather = draft.endWeather
        entry.dayWeatherRecords = draft.dayWeatherRecords
        entry.people = selectedPeople

        switch draft.kind {
        case .transit:
            guard let draftDetails = draft.transitDetails else {
                throw AutomationCandidateReviewError.missingDetails
            }
            if let details = entry.transitDetails {
                Self.copy(draftDetails, to: details)
            } else {
                let details = Self.copy(of: draftDetails)
                modelContext.insert(details)
                entry.transitDetails = details
            }
        case .placeVisit:
            guard let draftDetails = draft.placeVisitDetails else {
                throw AutomationCandidateReviewError.missingDetails
            }
            if let details = entry.placeVisitDetails {
                Self.copy(draftDetails, to: details)
            } else {
                let details = Self.copy(of: draftDetails)
                modelContext.insert(details)
                entry.placeVisitDetails = details
            }
        case .workout, .wakeUp:
            throw AutomationCandidateReviewError.unsupportedKind
        }
    }

    private static func copy(
        _ source: TransitDetails,
        to destination: TransitDetails
    ) {
        destination.type = source.type
        destination.sourceOrganizationName = source.sourceOrganizationName
        destination.sourceServiceIdentifier = source.sourceServiceIdentifier
        destination.originPlace = source.originPlace
        destination.originLocation = source.originLocation
        destination.originRawText = source.originRawText
        destination.destinationPlace = source.destinationPlace
        destination.destinationLocation = source.destinationLocation
        destination.destinationRawText = source.destinationRawText
        destination.durationSource = source.durationSource
        destination.distanceMeters = source.distanceMeters
        destination.recordedRoute = source.recordedRoute
        destination.recordedMotion = source.recordedMotion
        destination.recordedTransitMode = source.recordedTransitMode
        destination.originCandidates = source.originCandidates
        destination.destinationCandidates = source.destinationCandidates
        destination.unresolvedPeople = source.unresolvedPeople
        destination.fieldReviews = source.fieldReviews
    }

    private static func copy(of source: TransitDetails) -> TransitDetails {
        let copy = TransitDetails(type: source.type)
        Self.copy(source, to: copy)
        return copy
    }

    private static func copy(
        _ source: PlaceVisitDetails,
        to destination: PlaceVisitDetails
    ) {
        destination.description = source.description
        destination.place = source.place
        destination.location = source.location
        destination.placeRawText = source.placeRawText
        destination.candidates = source.candidates
        destination.unresolvedPeople = source.unresolvedPeople
        destination.fieldReviews = source.fieldReviews
    }

    private static func copy(
        of source: PlaceVisitDetails
    ) -> PlaceVisitDetails {
        let copy = PlaceVisitDetails()
        Self.copy(source, to: copy)
        return copy
    }

    func dismiss(
        candidate: AutomationCandidate,
        in modelContext: ModelContext
    ) -> Bool {
        do {
            try AutomationCandidateStore.dismiss(candidate, in: modelContext)
            return true
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private enum AutomationCandidateReviewError: LocalizedError {
    case kindChanged
    case missingDetails
    case unsupportedKind

    var errorDescription: String? {
        switch self {
        case .kindChanged:
            String(localized: "The candidate type changed unexpectedly.")
        case .missingDetails:
            String(localized: "The candidate details are incomplete.")
        case .unsupportedKind:
            String(localized: "This entry type cannot be accepted as an automation candidate.")
        }
    }
}
