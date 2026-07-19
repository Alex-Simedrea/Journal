//
//  TransitReviewModel.swift
//  Journal
//

import Foundation
import Observation
import SwiftData

enum TransitEndpoint: String, Equatable {
    case origin
    case destination
}

struct AddTransitPlaceRequest: Identifiable, Equatable {
    let id = UUID()
    let endpoint: TransitEndpoint
    let initialName: String
    let searchQuery: String
    let initialLocation: Location?
}

struct PersonAliasResolution: Identifiable, Equatable {
    let id = UUID()
    let rawText: String
    var personID: UUID?
}

@MainActor
@Observable
final class TransitReviewModel {
    var transitType: String
    var originPlaceID: UUID?
    var destinationPlaceID: UUID?
    var startTime: Date
    var endTime: Date
    var personResolutions: [PersonAliasResolution]
    var addPlaceRequest: AddTransitPlaceRequest?
    var errorMessage: String?

    let reviewsTransitType: Bool
    let reviewsEntryKind: Bool
    let reviewsOrigin: Bool
    let reviewsDestination: Bool
    let reviewsTime: Bool
    let reviewsPeople: Bool

    private let originalStartTime: Date?
    private let originalEndTime: Date?

    init(entry: LogEntry) {
        let details = entry.transitDetails
        let now = Date.now
        let resolvedEnd = entry.endTime ?? now
        let resolutions = (details?.unresolvedPeople ?? []).map {
            PersonAliasResolution(rawText: $0, personID: nil)
        }
        let shouldReviewOrigin = details?.originPlace == nil
            || details?.review(for: .origin) != nil
        let shouldReviewDestination = details?.destinationPlace == nil
            || details?.review(for: .destination) != nil
        let shouldReviewTime = entry.startTime == nil
            || entry.endTime == nil
            || entry.timeConfidence == .unresolved
            || details?.review(for: .time) != nil
        let shouldReviewPeople = !resolutions.isEmpty
            || details?.review(for: .people) != nil
        let hasLegacyGlobalReview = entry.needsReview
            && (details?.fieldReviews.isEmpty ?? true)
            && entry.entryKindReviewReason == nil

        transitType = details?.type ?? ""
        originPlaceID = details?.originPlace?.id
        destinationPlaceID = details?.destinationPlace?.id
        startTime = entry.startTime ?? resolvedEnd.addingTimeInterval(-30 * 60)
        endTime = resolvedEnd
        personResolutions = resolutions
        originalStartTime = entry.startTime
        originalEndTime = entry.endTime

        reviewsOrigin = shouldReviewOrigin
        reviewsDestination = shouldReviewDestination
        reviewsTime = shouldReviewTime
        reviewsPeople = shouldReviewPeople
        reviewsEntryKind = entry.entryKindReviewReason != nil

        reviewsTransitType = (details?.type.isEmpty ?? true)
            || details?.review(for: .transitType) != nil
            || (hasLegacyGlobalReview
                && !shouldReviewOrigin
                && !shouldReviewDestination
                && !shouldReviewTime
                && !shouldReviewPeople)
    }

    var canSave: Bool {
        !transitType.isEmpty
            && originPlaceID != nil
            && destinationPlaceID != nil
            && originPlaceID != destinationPlaceID
            && endTime > startTime
            && personResolutions.allSatisfy { $0.personID != nil }
    }

    func reviewReason(
        for field: TransitReviewField,
        in entry: LogEntry
    ) -> String? {
        entry.transitDetails?.review(for: field)?.reason
    }

    func requestPlace(
        for endpoint: TransitEndpoint,
        candidate: PlaceCandidate?,
        rawText: String?
    ) {
        let fallback = rawText ?? ""
        addPlaceRequest = AddTransitPlaceRequest(
            endpoint: endpoint,
            initialName: candidate?.name ?? fallback,
            searchQuery: candidate?.name ?? fallback,
            initialLocation: candidate?.location
        )
    }

    func placeWasAdded(_ place: Place, for endpoint: TransitEndpoint) {
        switch endpoint {
        case .origin:
            originPlaceID = place.id
        case .destination:
            destinationPlaceID = place.id
        }
    }

    func useJustNow() {
        let duration = max(endTime.timeIntervalSince(startTime), 30 * 60)
        endTime = .now
        startTime = endTime.addingTimeInterval(-duration)
    }

    func useEarlierToday() {
        let now = Date.now
        let startOfDay = Calendar.current.startOfDay(for: now)
        let proposedEnd = now.addingTimeInterval(-2 * 60 * 60)
        endTime = max(proposedEnd, startOfDay.addingTimeInterval(60 * 60))
        startTime = max(
            startOfDay,
            endTime.addingTimeInterval(-30 * 60)
        )
    }

    func save(
        entry: LogEntry,
        places: [Place],
        people: [Person],
        modelContext: ModelContext
    ) -> Bool {
        guard canSave,
              let details = entry.transitDetails,
              let origin = places.first(where: { $0.id == originPlaceID }),
              let destination = places.first(where: { $0.id == destinationPlaceID }) else {
            return false
        }

        details.type = transitType
        details.originPlace = origin
        details.destinationPlace = destination
        entry.startTime = startTime
        entry.endTime = endTime
        entry.startTimeZoneIdentifier = origin.location.timeZoneIdentifier
            ?? entry.creationTimeZoneIdentifier
        entry.endTimeZoneIdentifier = destination.location.timeZoneIdentifier
            ?? entry.creationTimeZoneIdentifier
        details.originCandidates = []
        details.destinationCandidates = []
        details.unresolvedPeople = []
        details.fieldReviews = []
        details.distanceMeters = nil

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

        let timeChanged = originalStartTime != startTime
            || originalEndTime != endTime
        if timeChanged || reviewsTime {
            entry.timeConfidence = .manualOverride
            details.durationSource = .manualOverride
        }

        addAlias(details.originRawText, to: origin)
        addAlias(details.destinationRawText, to: destination)
        entry.entryKindReviewReason = nil
        entry.needsReview = false
        let originalWeather = entry.weather
        entry.weather = nil

        do {
            try modelContext.save()
            EntryWeatherService.refreshInBackground(
                entry,
                in: modelContext
            )
            TransitDistanceService.refreshInBackground(
                entry,
                in: modelContext
            )
            return true
        } catch {
            entry.weather = originalWeather
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func addAlias(_ rawText: String?, to place: Place) {
        guard let rawText else { return }
        let normalized = TransitResolutionService.normalize(rawText)
        let knownNames = [place.name] + place.aliases
        guard !knownNames.contains(where: {
            TransitResolutionService.normalize($0) == normalized
        }) else {
            return
        }
        place.aliases.append(rawText)
    }

    private func addAlias(_ rawText: String, to person: Person) {
        let normalized = TransitResolutionService.normalize(rawText)
        let knownNames = [person.name] + person.aliases
        guard !knownNames.contains(where: {
            TransitResolutionService.normalize($0) == normalized
        }) else {
            return
        }
        person.aliases.append(rawText)
    }
}
