//
//  ManualTransitComposerModel.swift
//  Journal
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ManualTransitComposerModel {
    var transitType = ""
    var originPlaceID: UUID?
    var destinationPlaceID: UUID?
    var startTime = Date.now.addingTimeInterval(-30 * 60)
    var endTime = Date.now
    var selectedPeopleIDs: Set<UUID> = []
    var isSaving = false
    var errorMessage: String?

    var canSave: Bool {
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

    func save(
        places: [Place],
        people: [Person],
        modelContext: ModelContext
    ) async -> Bool {
        guard canSave,
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
            let entry = try TransitEntryStore.insert(
                draft: draft,
                rawInput: nil,
                in: modelContext
            )
            _ = try? await EntryWeatherService.populate(
                entry,
                in: modelContext
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
