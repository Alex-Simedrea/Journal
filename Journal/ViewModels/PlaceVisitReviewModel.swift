//
//  PlaceVisitReviewModel.swift
//  Journal
//

import Foundation
import Observation
import SwiftData

struct AddVisitPlaceRequest: Identifiable, Equatable {
    let id = UUID()
    let initialName: String
    let searchQuery: String
    let initialLocation: Location?
}

@MainActor
@Observable
final class PlaceVisitReviewModel {
    var placeID: UUID?
    var location: Location?
    var startTime: Date
    var endTime: Date
    var personResolutions: [PersonAliasResolution]
    var addPlaceRequest: AddVisitPlaceRequest?
    var errorMessage: String?

    let reviewsEntryKind: Bool
    let reviewsPlace: Bool
    let reviewsTime: Bool
    let reviewsPeople: Bool

    init(entry: LogEntry) {
        let details = entry.placeVisitDetails
        let fallbackEnd = entry.endTime ?? .now
        let fallbackStart = entry.startTime
            ?? fallbackEnd.addingTimeInterval(-60 * 60)
        let resolutions = (details?.unresolvedPeople ?? []).map {
            PersonAliasResolution(rawText: $0, personID: nil)
        }
        let resolvedLocation = details?.location ?? details?.place?.location
        placeID = details?.place?.id
        location = resolvedLocation
        startTime = fallbackStart
        endTime = max(fallbackEnd, fallbackStart.addingTimeInterval(60))
        personResolutions = resolutions
        reviewsEntryKind = entry.entryKindReviewReason != nil
        reviewsPlace = resolvedLocation == nil
            || details?.review(for: .place) != nil
        reviewsTime = entry.startTime == nil
            || entry.endTime == nil
            || details?.review(for: .time) != nil
        reviewsPeople = !resolutions.isEmpty
            || details?.review(for: .people) != nil
    }

    var canSave: Bool {
        location != nil
            && endTime > startTime
            && personResolutions.allSatisfy { $0.personID != nil }
    }

    func requestPlace(candidate: LocationCandidate) {
        addPlaceRequest = AddVisitPlaceRequest(
            initialName: candidate.name,
            searchQuery: candidate.name,
            initialLocation: candidate.location
        )
    }

    func placeWasAdded(_ place: Place) {
        placeID = place.id
        location = place.location
    }

    func selectLocation(_ selection: EntryLocationSelection) {
        placeID = selection.placeID
        location = selection.location
    }

    func useCandidate(_ candidate: LocationCandidate) {
        selectLocation(
            EntryLocationSelection(
                location: candidate.location,
                title: candidate.name
            )
        )
    }

    func reviewReason(
        for field: PlaceVisitReviewField,
        in entry: LogEntry
    ) -> String? {
        entry.placeVisitDetails?.review(for: field)?.reason
    }

    func save(
        entry: LogEntry,
        places: [Place],
        people: [Person],
        in modelContext: ModelContext
    ) -> Bool {
        let place = places.first(where: { $0.id == placeID })
        guard canSave,
              let details = entry.placeVisitDetails,
              let location = place?.location ?? location else {
            return false
        }

        details.place = place
        details.location = location
        details.candidates = []
        details.fieldReviews = []
        entry.startTime = startTime
        entry.endTime = endTime
        let zone = location.timeZoneIdentifier
            ?? entry.creationTimeZoneIdentifier
        entry.startTimeZoneIdentifier = zone
        entry.endTimeZoneIdentifier = zone
        entry.timeConfidence = .manualOverride

        for resolution in personResolutions {
            guard let personID = resolution.personID,
                  let person = people.first(where: { $0.id == personID }) else {
                continue
            }
            if !entry.people.contains(where: { $0.id == person.id }) {
                entry.people.append(person)
            }
            addAlias(resolution.rawText, to: person)
        }
        details.unresolvedPeople = []
        if let place { addAlias(details.placeRawText, to: place) }
        entry.entryKindReviewReason = nil
        entry.needsReview = false
        entry.weather = nil
        entry.endWeather = nil

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

    private func addAlias(_ rawText: String?, to place: Place) {
        guard let rawText else { return }
        let known = [place.name] + place.aliases
        guard !known.contains(where: {
            TransitResolutionService.normalize($0)
                == TransitResolutionService.normalize(rawText)
        }) else { return }
        place.aliases.append(rawText)
    }

    private func addAlias(_ rawText: String, to person: Person) {
        let known = [person.name] + person.aliases
        guard !known.contains(where: {
            TransitResolutionService.normalize($0)
                == TransitResolutionService.normalize(rawText)
        }) else { return }
        person.aliases.append(rawText)
    }
}
