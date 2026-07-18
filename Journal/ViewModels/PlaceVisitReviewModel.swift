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
        placeID = details?.place?.id
        startTime = fallbackStart
        endTime = max(fallbackEnd, fallbackStart.addingTimeInterval(60))
        personResolutions = resolutions
        reviewsEntryKind = entry.entryKindReviewReason != nil
        reviewsPlace = details?.place == nil
            || details?.review(for: .place) != nil
        reviewsTime = entry.startTime == nil
            || entry.endTime == nil
            || details?.review(for: .time) != nil
        reviewsPeople = !resolutions.isEmpty
            || details?.review(for: .people) != nil
    }

    var canSave: Bool {
        placeID != nil
            && endTime > startTime
            && personResolutions.allSatisfy { $0.personID != nil }
    }

    func requestPlace(candidate: PlaceCandidate?, rawText: String?) {
        let fallback = rawText ?? ""
        addPlaceRequest = AddVisitPlaceRequest(
            initialName: candidate?.name ?? fallback,
            searchQuery: candidate?.name ?? fallback,
            initialLocation: candidate?.location
        )
    }

    func placeWasAdded(_ place: Place) {
        placeID = place.id
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
        guard canSave,
              let details = entry.placeVisitDetails,
              let place = places.first(where: { $0.id == placeID }) else {
            return false
        }

        details.place = place
        details.candidates = []
        details.fieldReviews = []
        entry.startTime = startTime
        entry.endTime = endTime
        let zone = place.location.timeZoneIdentifier
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
        addAlias(details.placeRawText, to: place)
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
