//
//  TransitEditModel.swift
//  Journal
//

import Foundation
import CoreLocation
import Observation
import SwiftData

@MainActor
@Observable
final class TransitEditModel {
    var transitType: String
    var originPlaceID: UUID?
    var destinationPlaceID: UUID?
    var originLocation: Location?
    var destinationLocation: Location?
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
        originLocation = entry.transitDetails?.originLocation
            ?? entry.transitDetails?.originPlace?.location
        destinationLocation = entry.transitDetails?.destinationLocation
            ?? entry.transitDetails?.destinationPlace?.location
        startTime = fallbackStart
        endTime = max(fallbackEnd, fallbackStart.addingTimeInterval(60))
        selectedPeopleIDs = Set(entry.people.map(\.id))
        originalStartTime = entry.startTime
        originalEndTime = entry.endTime
    }

    var canSave: Bool {
        !transitType.isEmpty
            && originLocation != nil
            && destinationLocation != nil
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

    func selectOrigin(_ selection: EntryLocationSelection) {
        originPlaceID = selection.placeID
        originLocation = selection.location
    }

    func selectDestination(_ selection: EntryLocationSelection) {
        destinationPlaceID = selection.placeID
        destinationLocation = selection.location
    }

    func save(
        entry: LogEntry,
        places: [Place],
        people: [Person],
        in modelContext: ModelContext
    ) -> Bool {
        let origin = places.first(where: { $0.id == originPlaceID })
        let destination = places.first(where: { $0.id == destinationPlaceID })
        guard canSave,
              let details = entry.transitDetails,
              let originLocation = origin?.location ?? originLocation,
              let destinationLocation = destination?.location ?? destinationLocation,
              CLLocation(latitude: originLocation.latitude, longitude: originLocation.longitude)
                .distance(from: CLLocation(latitude: destinationLocation.latitude, longitude: destinationLocation.longitude)) > 1 else {
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
        details.originLocation = originLocation
        details.destinationPlace = destination
        details.destinationLocation = destinationLocation
        details.originCandidates = []
        details.destinationCandidates = []
        details.unresolvedPeople = []
        details.fieldReviews = []
        details.distanceMeters = nil

        entry.startTime = startTime
        entry.endTime = endTime
        entry.startTimeZoneIdentifier = originLocation.timeZoneIdentifier
            ?? entry.creationTimeZoneIdentifier
        entry.endTimeZoneIdentifier = destinationLocation.timeZoneIdentifier
            ?? entry.creationTimeZoneIdentifier
        entry.people = people.filter { selectedPeopleIDs.contains($0.id) }
        entry.needsReview = entry.entryKindReviewReason != nil

        if didChangeTime || entry.timeConfidence == .unresolved {
            entry.timeConfidence = .manualOverride
            details.durationSource = .manualOverride
        }
        entry.weather = nil
        entry.endWeather = nil

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
            originalState.restore(entry: entry, details: details)
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private struct TransitEditOriginalState {
    let transitType: String
    let originPlace: Place?
    let originLocation: Location?
    let destinationPlace: Place?
    let destinationLocation: Location?
    let durationSource: DurationSource
    let distanceMeters: Double?
    let originCandidates: [LocationCandidate]
    let destinationCandidates: [LocationCandidate]
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
    let endWeather: EntryWeather?

    init(entry: LogEntry, details: TransitDetails) {
        transitType = details.type
        originPlace = details.originPlace
        originLocation = details.originLocation
        destinationPlace = details.destinationPlace
        destinationLocation = details.destinationLocation
        durationSource = details.durationSource
        distanceMeters = details.distanceMeters
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
        endWeather = entry.endWeather
    }

    func restore(entry: LogEntry, details: TransitDetails) {
        details.type = transitType
        details.originPlace = originPlace
        details.originLocation = originLocation
        details.destinationPlace = destinationPlace
        details.destinationLocation = destinationLocation
        details.durationSource = durationSource
        details.distanceMeters = distanceMeters
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
        entry.endWeather = endWeather
    }
}
