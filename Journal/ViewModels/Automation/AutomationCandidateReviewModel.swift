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
        draft.transitDetails?.distanceMeters = materializedEntry
            .transitDetails?.distanceMeters
        return draft
    }

    func commit(
        _ entry: LogEntry,
        candidate: AutomationCandidate,
        in modelContext: ModelContext
    ) async -> Bool {
        guard candidate.status == .pending else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let storedEntry = try materializedEntry(
                for: candidate,
                in: modelContext
            )
            let acceptedEntry: LogEntry
            if let storedEntry {
                apply(entry, to: storedEntry, in: modelContext)
                acceptedEntry = storedEntry
            } else {
                entry.id = candidate.id
                modelContext.insert(entry)
                acceptedEntry = entry
            }
            AutomationCandidateStore.markAccepted(
                candidate,
                entryID: acceptedEntry.id
            )
            try modelContext.save()
            _ = try? await EntryWeatherService.populate(
                acceptedEntry,
                in: modelContext
            )
            if acceptedEntry.kind == .transit {
                TransitDistanceService.refreshInBackground(
                    acceptedEntry,
                    in: modelContext
                )
            }
            try? await PhotoAutoLinkService.synchronize(in: modelContext)
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
        return try modelContext.fetch(
            FetchDescriptor<LogEntry>(
                predicate: #Predicate { $0.id == id }
            )
        ).first
    }

    private func apply(
        _ draft: LogEntry,
        to entry: LogEntry,
        in modelContext: ModelContext
    ) {
        let oldTransitDetails = entry.transitDetails
        let oldVisitDetails = entry.placeVisitDetails
        let oldWorkoutDetails = entry.workoutDetails

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
        entry.photoReferences = draft.photoReferences
        entry.weather = draft.weather
        entry.endWeather = draft.endWeather
        entry.dayWeatherRecords = draft.dayWeatherRecords
        entry.people = draft.people

        entry.transitDetails = draft.transitDetails
        entry.placeVisitDetails = draft.placeVisitDetails
        entry.workoutDetails = draft.workoutDetails
        if let details = draft.transitDetails { modelContext.insert(details) }
        if let details = draft.placeVisitDetails { modelContext.insert(details) }
        if let details = draft.workoutDetails { modelContext.insert(details) }
        if let oldTransitDetails { modelContext.delete(oldTransitDetails) }
        if let oldVisitDetails { modelContext.delete(oldVisitDetails) }
        if let oldWorkoutDetails { modelContext.delete(oldWorkoutDetails) }
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
