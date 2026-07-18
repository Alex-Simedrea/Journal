//
//  EntryKindConversionModel.swift
//  Journal
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class EntryKindConversionModel {
    let targetKind: LogKind
    var transitType = ""
    var originPlaceID: UUID?
    var destinationPlaceID: UUID?
    var visitPlaceID: UUID?
    var startTime: Date
    var endTime: Date
    var selectedPeopleIDs: Set<UUID>
    var errorMessage: String?

    init(entry: LogEntry, targetKind: LogKind) {
        self.targetKind = targetKind
        let fallbackEnd = entry.endTime ?? .now
        let fallbackStart = entry.startTime
            ?? fallbackEnd.addingTimeInterval(-60 * 60)
        startTime = fallbackStart
        endTime = max(fallbackEnd, fallbackStart.addingTimeInterval(60))
        selectedPeopleIDs = Set(entry.people.map(\.id))

        switch targetKind {
        case .placeVisit:
            let details = entry.transitDetails
            visitPlaceID = details?.destinationPlace?.id
                ?? details?.originPlace?.id
        case .transit:
            destinationPlaceID = entry.placeVisitDetails?.place?.id
        case .workout:
            break
        }
    }

    var canSave: Bool {
        guard endTime > startTime else { return false }
        switch targetKind {
        case .transit:
            return !transitType.isEmpty
                && originPlaceID != nil
                && destinationPlaceID != nil
                && originPlaceID != destinationPlaceID
        case .placeVisit:
            return visitPlaceID != nil
        case .workout:
            return false
        }
    }

    var navigationTitle: LocalizedStringResource {
        switch targetKind {
        case .transit: "Convert to Transit"
        case .placeVisit: "Convert to Visit"
        case .workout: "Workout"
        }
    }

    func prepare(transitTypes: [TransitType]) {
        if targetKind == .transit, transitType.isEmpty {
            transitType = transitTypes.first?.canonicalName ?? ""
        }
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
        guard canSave else { return false }

        switch targetKind {
        case .transit:
            guard let origin = places.first(where: { $0.id == originPlaceID }),
                  let destination = places.first(where: {
                      $0.id == destinationPlaceID
                  }) else { return false }
            let oldDetails = entry.placeVisitDetails
            entry.placeVisitDetails = nil
            if let oldDetails {
                modelContext.delete(oldDetails)
            }
            entry.transitDetails = TransitDetails(
                type: transitType,
                originPlace: origin,
                originRawText: origin.name,
                destinationPlace: destination,
                destinationRawText: destination.name,
                durationSource: .manualOverride
            )
            entry.startTimeZoneIdentifier = origin.location.timeZoneIdentifier
                ?? entry.creationTimeZoneIdentifier
            entry.endTimeZoneIdentifier = destination.location.timeZoneIdentifier
                ?? entry.creationTimeZoneIdentifier
        case .placeVisit:
            guard let place = places.first(where: { $0.id == visitPlaceID }) else {
                return false
            }
            let oldDetails = entry.transitDetails
            entry.transitDetails = nil
            if let oldDetails {
                modelContext.delete(oldDetails)
            }
            entry.placeVisitDetails = PlaceVisitDetails(
                place: place,
                placeRawText: place.name
            )
            let zone = place.location.timeZoneIdentifier
                ?? entry.creationTimeZoneIdentifier
            entry.startTimeZoneIdentifier = zone
            entry.endTimeZoneIdentifier = zone
        case .workout:
            return false
        }

        entry.kind = targetKind
        entry.startTime = startTime
        entry.endTime = endTime
        entry.timeConfidence = .manualOverride
        entry.people = people.filter { selectedPeopleIDs.contains($0.id) }
        entry.entryKindReviewReason = nil
        entry.needsReview = false
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
