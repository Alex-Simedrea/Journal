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

        do {
            _ = try EntryLinkingService.reconcile(in: modelContext)
            try EntryLinkingService.validateTimeEdit(
                entry: entry,
                startTime: startTime,
                endTime: endTime,
                in: modelContext
            )
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

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
            try EntryLinkingService.propagateTimeEdit(
                from: entry,
                in: modelContext
            )
            try EntryLinkingService.propagateLocationEdit(
                from: entry,
                role: .origin,
                in: modelContext
            )
            try EntryLinkingService.propagateLocationEdit(
                from: entry,
                role: .destination,
                in: modelContext
            )
            try JournalPersistence.save(modelContext)
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
            modelContext.rollback()
            errorMessage = error.localizedDescription
            return false
        }
    }
}
