//
//  PlaceVisitComposerModel.swift
//  Journal
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class PlaceVisitComposerModel {
    var placeID: UUID?
    var startTime = Date.now.addingTimeInterval(-60 * 60)
    var endTime = Date.now
    var selectedPeopleIDs: Set<UUID> = []
    var isSaving = false
    var errorMessage: String?

    var canSave: Bool {
        placeID != nil && endTime > startTime && !isSaving
    }

    func togglePerson(_ id: UUID) {
        if selectedPeopleIDs.contains(id) {
            selectedPeopleIDs.remove(id)
        } else {
            selectedPeopleIDs.insert(id)
        }
    }

    func save(
        places: [Place],
        people: [Person],
        modelContext: ModelContext
    ) async -> Bool {
        guard canSave,
              let place = places.first(where: { $0.id == placeID }) else {
            return false
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let draft = ResolvedPlaceVisitDraft(
            place: place,
            placeRawText: place.name,
            startTime: startTime,
            endTime: endTime,
            timeConfidence: .manualOverride,
            people: people.filter { selectedPeopleIDs.contains($0.id) },
            candidates: [],
            unresolvedPeople: [],
            fieldReviews: [],
            entryKindReviewReason: nil
        )

        do {
            let entry = try PlaceVisitEntryStore.insert(
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
