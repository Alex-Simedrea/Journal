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
    var originLocation: Location?
    var destinationLocation: Location?
    var visitLocation: Location?
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
            visitLocation = details?.destinationLocation
                ?? details?.destinationPlace?.location
                ?? details?.originLocation
                ?? details?.originPlace?.location
        case .transit:
            destinationPlaceID = entry.placeVisitDetails?.place?.id
            destinationLocation = entry.placeVisitDetails?.location
                ?? entry.placeVisitDetails?.place?.location
        case .workout, .wakeUp:
            break
        }
    }

    var canSave: Bool {
        guard endTime > startTime else { return false }
        switch targetKind {
        case .transit:
            return !transitType.isEmpty
                && (originLocation != nil || originPlaceID != nil)
                && (destinationLocation != nil || destinationPlaceID != nil)
        case .placeVisit:
            return visitLocation != nil || visitPlaceID != nil
        case .workout, .wakeUp:
            return false
        }
    }

    var navigationTitle: LocalizedStringResource {
        switch targetKind {
        case .transit: "Convert to Transit"
        case .placeVisit: "Convert to Visit"
        case .workout: "Workout"
        case .wakeUp: "Wake up"
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

    func selectOrigin(_ selection: EntryLocationSelection) {
        originPlaceID = selection.placeID
        originLocation = selection.location
    }

    func selectDestination(_ selection: EntryLocationSelection) {
        destinationPlaceID = selection.placeID
        destinationLocation = selection.location
    }

    func selectVisitLocation(_ selection: EntryLocationSelection) {
        visitPlaceID = selection.placeID
        visitLocation = selection.location
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
            let origin = places.first(where: { $0.id == originPlaceID })
            let destination = places.first(where: { $0.id == destinationPlaceID })
            guard let originLocation = origin?.location ?? originLocation,
                  let destinationLocation = destination?.location ?? destinationLocation else {
                return false
            }
            let oldDetails = entry.placeVisitDetails
            entry.placeVisitDetails = nil
            if let oldDetails {
                modelContext.delete(oldDetails)
            }
            entry.transitDetails = TransitDetails(
                type: transitType,
                originPlace: origin,
                originLocation: originLocation.withFallbackDisplayName(
                    origin?.name
                ),
                originRawText: origin?.name ?? originLocation.preferredName,
                destinationPlace: destination,
                destinationLocation: destinationLocation.withFallbackDisplayName(
                    destination?.name
                ),
                destinationRawText: destination?.name ?? destinationLocation.preferredName,
                durationSource: .manualOverride
            )
            entry.startTimeZoneIdentifier = originLocation.timeZoneIdentifier
                ?? entry.creationTimeZoneIdentifier
            entry.endTimeZoneIdentifier = destinationLocation.timeZoneIdentifier
                ?? entry.creationTimeZoneIdentifier
        case .placeVisit:
            let place = places.first(where: { $0.id == visitPlaceID })
            guard let visitLocation = place?.location ?? visitLocation else { return false }
            let oldDetails = entry.transitDetails
            entry.transitDetails = nil
            if let oldDetails {
                modelContext.delete(oldDetails)
            }
            entry.placeVisitDetails = PlaceVisitDetails(
                place: place,
                location: visitLocation.withFallbackDisplayName(place?.name),
                placeRawText: place?.name ?? visitLocation.preferredName
            )
            let zone = visitLocation.timeZoneIdentifier
                ?? entry.creationTimeZoneIdentifier
            entry.startTimeZoneIdentifier = zone
            entry.endTimeZoneIdentifier = zone
        case .workout, .wakeUp:
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
