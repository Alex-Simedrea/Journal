//
//  ManualTransitComposerModel.swift
//  Journal
//

import Foundation
import CoreLocation
import Observation
import SwiftData

@MainActor
@Observable
final class ManualTransitComposerModel {
    var transitType = ""
    var originPlaceID: UUID?
    var destinationPlaceID: UUID?
    var originLocation: Location?
    var destinationLocation: Location?
    var startTime = Date.now.addingTimeInterval(-30 * 60)
    var endTime = Date.now
    var selectedPeopleIDs: Set<UUID> = []
    var isSaving = false
    var errorMessage: String?

    var canSave: Bool {
        !transitType.isEmpty
            && (originLocation != nil || originPlaceID != nil)
            && (destinationLocation != nil || destinationPlaceID != nil)
            && (originPlaceID == nil || destinationPlaceID == nil
                || originPlaceID != destinationPlaceID)
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

    func selectOrigin(_ selection: EntryLocationSelection) {
        originPlaceID = selection.placeID
        originLocation = selection.location
    }

    func selectDestination(_ selection: EntryLocationSelection) {
        destinationPlaceID = selection.placeID
        destinationLocation = selection.location
    }

    func save(
        places: [Place],
        people: [Person],
        modelContext: ModelContext
    ) async -> Bool {
        let origin = places.first(where: { $0.id == originPlaceID })
        let destination = places.first(where: { $0.id == destinationPlaceID })
        let resolvedOrigin = origin?.location ?? originLocation
        let resolvedDestination = destination?.location ?? destinationLocation
        guard let resolvedOrigin, let resolvedDestination,
              CLLocation(latitude: resolvedOrigin.latitude, longitude: resolvedOrigin.longitude)
                .distance(from: CLLocation(latitude: resolvedDestination.latitude, longitude: resolvedDestination.longitude)) > 1,
              endTime > startTime,
              !transitType.isEmpty else {
            return false
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let selectedPeople = people.filter { selectedPeopleIDs.contains($0.id) }
        let draft = ResolvedTransitDraft(
            transitType: transitType,
            originPlace: origin,
            originLocation: resolvedOrigin,
            originRawText: origin?.name ?? resolvedOrigin.preferredName,
            destinationPlace: destination,
            destinationLocation: resolvedDestination,
            destinationRawText: destination?.name ?? resolvedDestination.preferredName,
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
