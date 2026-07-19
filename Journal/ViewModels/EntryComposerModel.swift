//
//  EntryComposerModel.swift
//  Journal
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class EntryComposerModel {
    var input = ""
    var isSaving = false
    var errorMessage: String?

    var canSubmit: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving
    }

    var isShowingError: Bool {
        get { errorMessage != nil }
        set {
            if !newValue {
                errorMessage = nil
            }
        }
    }

    func submit(
        places: [Place],
        people: [Person],
        transitTypes: [TransitType],
        selectedDay: TimelineDayKey,
        modelContext: ModelContext
    ) async -> Bool {
        let rawInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else { return false }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let currentLocation = try await LocationService.shared
                .captureCurrentLocation()
            let now = Date.now
            let historyEntries = try EntryPromptHistoryService.entries(
                around: selectedDay,
                in: modelContext
            )
            let statistics = try PlaceVisitStatisticsService.fetch(
                in: modelContext
            )
            let result = try await EntryLanguageModelService.extract(
                input: rawInput,
                context: EntryPromptContext(
                    places: places,
                    people: people,
                    transitTypes: transitTypes,
                    visitStatisticsByPlaceID: statistics,
                    selectedDay: selectedDay,
                    selectedDayEntries: historyEntries,
                    currentDate: now,
                    currentLocation: currentLocation
                )
            )

            switch result.generatedLog {
            case .transit(let generated, let entryKindReview):
                var draft = TransitResolutionService.resolve(
                    generated: generated,
                    references: result.references,
                    toolSearches: result.toolSearches,
                    rawInput: rawInput,
                    people: people,
                    transitTypes: transitTypes,
                    currentLocation: currentLocation,
                    now: now,
                    selectedDayEntries: historyEntries
                )
                draft.entryKindReviewReason = reviewReason(entryKindReview)
                let entry = try TransitEntryStore.insert(
                    draft: draft,
                    rawInput: rawInput,
                    modelExchange: result.exchange,
                    in: modelContext
                )
                _ = try? await EntryWeatherService.populate(
                    entry,
                    in: modelContext
                )
            case .placeVisit(let generated, let entryKindReview):
                let draft = PlaceVisitResolutionService.resolve(
                    generated: generated,
                    entryKindReview: entryKindReview,
                    references: result.references,
                    toolSearches: result.toolSearches,
                    rawInput: rawInput,
                    people: people
                )
                let entry = try PlaceVisitEntryStore.insert(
                    draft: draft,
                    rawInput: rawInput,
                    modelExchange: result.exchange,
                    in: modelContext
                )
                _ = try? await EntryWeatherService.populate(
                    entry,
                    in: modelContext
                )
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func reviewReason(_ review: GeneratedFieldReview) -> String? {
        guard review.needsReview else { return nil }
        let reason = review.reason?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return reason?.isEmpty == false
            ? reason
            : String(localized: "The entry type is ambiguous.")
    }
}
