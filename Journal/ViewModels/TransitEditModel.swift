//
//  TransitEditModel.swift
//  Journal
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TransitEditModel {
    var transitType: String
    var originPlaceID: UUID?
    var destinationPlaceID: UUID?
    var startTime: Date
    var endTime: Date
    var selectedPeopleIDs: Set<UUID>
    var errorMessage: String?

    private let originalStartTime: Date?
    private let originalEndTime: Date?

    init(entry: LogEntry) {
        let fallbackEnd = entry.endTime ?? .now
        let fallbackStart = entry.startTime
            ?? fallbackEnd.addingTimeInterval(-30 * 60)

        transitType = entry.transitDetails?.type ?? ""
        originPlaceID = entry.transitDetails?.originPlace?.id
        destinationPlaceID = entry.transitDetails?.destinationPlace?.id
        startTime = fallbackStart
        endTime = max(fallbackEnd, fallbackStart.addingTimeInterval(60))
        selectedPeopleIDs = Set(entry.people.map(\.id))
        originalStartTime = entry.startTime
        originalEndTime = entry.endTime
    }

    var canSave: Bool {
        !transitType.isEmpty
            && originPlaceID != nil
            && destinationPlaceID != nil
            && originPlaceID != destinationPlaceID
            && endTime > startTime
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
        entry: LogEntry,
        places: [Place],
        people: [Person],
        in modelContext: ModelContext
    ) -> Bool {
        guard canSave,
              let details = entry.transitDetails,
              let origin = places.first(where: { $0.id == originPlaceID }),
              let destination = places.first(where: { $0.id == destinationPlaceID }) else {
            return false
        }

        let originalState = TransitEditOriginalState(
            entry: entry,
            details: details
        )
        let didChangeTime = originalStartTime != startTime
            || originalEndTime != endTime

        details.type = transitType
        details.originPlace = origin
        details.destinationPlace = destination
        details.originCandidates = []
        details.destinationCandidates = []
        details.unresolvedPeople = []
        details.fieldReviews = []

        entry.startTime = startTime
        entry.endTime = endTime
        entry.startTimeZoneIdentifier = origin.location.timeZoneIdentifier
            ?? entry.creationTimeZoneIdentifier
        entry.endTimeZoneIdentifier = destination.location.timeZoneIdentifier
            ?? entry.creationTimeZoneIdentifier
        entry.people = people.filter { selectedPeopleIDs.contains($0.id) }
        entry.needsReview = entry.entryKindReviewReason != nil

        if didChangeTime || entry.timeConfidence == .unresolved {
            entry.timeConfidence = .manualOverride
            details.durationSource = .manualOverride
        }
        entry.weather = nil

        do {
            try modelContext.save()
            EntryWeatherService.refreshInBackground(
                entry,
                in: modelContext
            )
            return true
        } catch {
            originalState.restore(entry: entry, details: details)
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private struct TransitEditOriginalState {
    let transitType: String
    let originPlace: Place?
    let destinationPlace: Place?
    let durationSource: DurationSource
    let originCandidates: [PlaceCandidate]
    let destinationCandidates: [PlaceCandidate]
    let unresolvedPeople: [String]
    let fieldReviews: [TransitFieldReview]
    let startTime: Date?
    let endTime: Date?
    let startTimeZoneIdentifier: String
    let endTimeZoneIdentifier: String
    let timeConfidence: TimeConfidence
    let people: [Person]
    let needsReview: Bool
    let weather: EntryWeather?

    init(entry: LogEntry, details: TransitDetails) {
        transitType = details.type
        originPlace = details.originPlace
        destinationPlace = details.destinationPlace
        durationSource = details.durationSource
        originCandidates = details.originCandidates
        destinationCandidates = details.destinationCandidates
        unresolvedPeople = details.unresolvedPeople
        fieldReviews = details.fieldReviews
        startTime = entry.startTime
        endTime = entry.endTime
        startTimeZoneIdentifier = entry.startTimeZoneIdentifier
        endTimeZoneIdentifier = entry.endTimeZoneIdentifier
        timeConfidence = entry.timeConfidence
        people = entry.people
        needsReview = entry.needsReview
        weather = entry.weather
    }

    func restore(entry: LogEntry, details: TransitDetails) {
        details.type = transitType
        details.originPlace = originPlace
        details.destinationPlace = destinationPlace
        details.durationSource = durationSource
        details.originCandidates = originCandidates
        details.destinationCandidates = destinationCandidates
        details.unresolvedPeople = unresolvedPeople
        details.fieldReviews = fieldReviews
        entry.startTime = startTime
        entry.endTime = endTime
        entry.startTimeZoneIdentifier = startTimeZoneIdentifier
        entry.endTimeZoneIdentifier = endTimeZoneIdentifier
        entry.timeConfidence = timeConfidence
        entry.people = people
        entry.needsReview = needsReview
        entry.weather = weather
    }
}
