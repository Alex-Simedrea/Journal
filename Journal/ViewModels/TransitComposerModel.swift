//
//  TransitComposerModel.swift
//  Journal
//

import Foundation
import Observation
import SwiftData

enum TransitComposerMode: String, Identifiable {
    case naturalLanguage
    case manual

    var id: String { rawValue }
}

@MainActor
@Observable
final class TransitComposerModel {
    var naturalLanguageInput = ""
    var transitType = ""
    var originPlaceID: UUID?
    var destinationPlaceID: UUID?
    var startTime = Date.now.addingTimeInterval(-30 * 60)
    var endTime = Date.now
    var selectedPeopleIDs: Set<UUID> = []
    var isSaving = false
    var errorMessage: String?

    var canSubmitNaturalLanguage: Bool {
        !naturalLanguageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving
    }

    var canSaveManual: Bool {
        !transitType.isEmpty
            && originPlaceID != nil
            && destinationPlaceID != nil
            && originPlaceID != destinationPlaceID
            && endTime > startTime
            && !isSaving
    }

    func prepare(transitTypes: [TransitType]) {
        if transitType.isEmpty {
            transitType = transitTypes.first?.canonicalName ?? ""
        }
    }

    func togglePerson(_ personID: UUID) {
        if selectedPeopleIDs.contains(personID) {
            selectedPeopleIDs.remove(personID)
        } else {
            selectedPeopleIDs.insert(personID)
        }
    }

    func submitNaturalLanguage(
        places: [Place],
        people: [Person],
        transitTypes: [TransitType],
        modelContext: ModelContext
    ) async -> Bool {
        let input = naturalLanguageInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return false }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let currentLocation = try await LocationService.shared
                .captureCurrentLocation()
            let now = Date.now
            let modelResult = try await TransitLanguageModelService.extract(
                input: input,
                context: TransitPromptContext(
                    places: places,
                    people: people,
                    transitTypes: transitTypes,
                    currentDate: now,
                    currentLocation: currentLocation
                )
            )
            let resolved = TransitResolutionService.resolve(
                generated: modelResult.generatedLog,
                references: modelResult.references,
                toolSearches: modelResult.toolSearches,
                rawInput: input,
                people: people,
                transitTypes: transitTypes,
                currentLocation: currentLocation,
                now: now
            )
            _ = try TransitEntryStore.insert(
                draft: resolved,
                rawInput: input,
                modelExchange: modelResult.exchange,
                in: modelContext
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveManual(
        places: [Place],
        people: [Person],
        modelContext: ModelContext
    ) -> Bool {
        guard canSaveManual,
              let origin = places.first(where: { $0.id == originPlaceID }),
              let destination = places.first(where: { $0.id == destinationPlaceID }) else {
            return false
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let selectedPeople = people.filter { selectedPeopleIDs.contains($0.id) }
        let draft = ResolvedTransitDraft(
            transitType: transitType,
            originPlace: origin,
            originRawText: origin.name,
            destinationPlace: destination,
            destinationRawText: destination.name,
            startTime: startTime,
            endTime: endTime,
            timeConfidence: .manualOverride,
            people: selectedPeople,
            durationSource: .manualOverride,
            originCandidates: [],
            destinationCandidates: [],
            unresolvedPeople: [],
            fieldReviews: []
        )

        do {
            _ = try TransitEntryStore.insert(
                draft: draft,
                rawInput: nil,
                in: modelContext
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
