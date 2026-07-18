//
//  PlaceVisitEditModel.swift
//  Journal
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class PlaceVisitEditModel {
    var placeID: UUID?
    var startTime: Date
    var endTime: Date
    var selectedPeopleIDs: Set<UUID>
    var errorMessage: String?

    init(entry: LogEntry) {
        let fallbackEnd = entry.endTime ?? .now
        let fallbackStart = entry.startTime
            ?? fallbackEnd.addingTimeInterval(-60 * 60)
        placeID = entry.placeVisitDetails?.place?.id
        startTime = fallbackStart
        endTime = max(fallbackEnd, fallbackStart.addingTimeInterval(60))
        selectedPeopleIDs = Set(entry.people.map(\.id))
    }

    var canSave: Bool {
        placeID != nil && endTime > startTime
    }

    func togglePerson(_ id: UUID) {
        if selectedPeopleIDs.contains(id) {
            selectedPeopleIDs.remove(id)
        } else {
            selectedPeopleIDs.insert(id)
        }
    }

    func save(
        entry: LogEntry,
        places: [Place],
        people: [Person],
        in modelContext: ModelContext
    ) -> Bool {
        guard canSave,
              let details = entry.placeVisitDetails,
              let place = places.first(where: { $0.id == placeID }) else {
            return false
        }

        details.place = place
        details.candidates = []
        details.unresolvedPeople = []
        details.fieldReviews = []
        entry.startTime = startTime
        entry.endTime = endTime
        let zone = place.location.timeZoneIdentifier
            ?? entry.creationTimeZoneIdentifier
        entry.startTimeZoneIdentifier = zone
        entry.endTimeZoneIdentifier = zone
        entry.timeConfidence = .manualOverride
        entry.people = people.filter { selectedPeopleIDs.contains($0.id) }
        entry.needsReview = entry.entryKindReviewReason != nil
        entry.weather = nil

        do {
            try modelContext.save()
            EntryWeatherService.refreshInBackground(
                entry,
                in: modelContext
            )
            return true
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            return false
        }
    }
}
