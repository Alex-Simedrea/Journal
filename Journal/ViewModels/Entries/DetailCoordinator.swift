//
//  EntryDetailCoordinator.swift
//  Journal
//

import Foundation
import Observation

enum EntryDetailLocationRole: String, Hashable, Identifiable, Sendable {
    case place
    case origin
    case destination

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .place: "Location"
        case .origin: "Origin"
        case .destination: "Destination"
        }
    }
}

enum EntryDetailRoute: Hashable, Identifiable, Sendable {
    case details
    case time
    case people
    case photos
    case transitMetadata
    case locations
    case location(EntryDetailLocationRole)
    case entryKind
    case addPerson
    case addPlace(EntryDetailLocationRole)
    case advanced

    var id: String {
        switch self {
        case .details: "details"
        case .time: "time"
        case .people: "people"
        case .photos: "photos"
        case .transitMetadata: "transit-metadata"
        case .locations: "locations"
        case .location(let role): "location-\(role.rawValue)"
        case .entryKind: "entry-kind"
        case .addPerson: "add-person"
        case .addPlace(let role): "add-place-\(role.rawValue)"
        case .advanced: "advanced"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .details: "Details"
        case .time: "Time"
        case .people: "People"
        case .photos: "Photos"
        case .transitMetadata: "Transit"
        case .locations: "Locations"
        case .location(let role): role.title
        case .entryKind: "Entry Type"
        case .addPerson: "New Person"
        case .addPlace: "New Place"
        case .advanced: "Advanced"
        }
    }

    var hasConfirmationAction: Bool {
        switch self {
        case .time, .people, .photos, .transitMetadata, .location,
             .entryKind, .addPerson, .addPlace:
            true
        case .details, .locations, .advanced:
            false
        }
    }
}

@MainActor
@Observable
final class EntryDetailCoordinator {
    private(set) var path: [EntryDetailRoute] = [.details]
    private(set) var movesForward = true
    var errorMessage: String?
    let session: EntryDetailEditSession

    init(entry: LogEntry) {
        session = EntryDetailEditSession(entry: entry)
    }

    var route: EntryDetailRoute { path.last ?? .details }

    var isDirty: Bool {
        path.contains { session.isDirty(for: $0) }
    }

    func present(_ route: EntryDetailRoute) {
        movesForward = true
        path.append(route)
        errorMessage = nil
    }

    func goBack(discardingChanges: Bool = true) {
        guard path.count > 1 else { return }
        if discardingChanges {
            session.restoreDraft(for: route)
        }
        movesForward = false
        path.removeLast()
        errorMessage = nil
    }

    func returnToDetails(entry: LogEntry) {
        movesForward = false
        session.reload(from: entry)
        path = [.details]
        errorMessage = nil
    }

    func returnToLocations(entry: LogEntry) {
        movesForward = false
        session.reload(from: entry)
        path = [.details, .locations]
        errorMessage = nil
    }
}

@MainActor
@Observable
final class EntryDetailEditSession {
    var startTime: Date
    var endTime: Date
    var startTimeZoneIdentifier: String
    var endTimeZoneIdentifier: String
    var selectedPeopleIDs: Set<UUID>
    var photoReferences: [PhotoReference]
    var transitType: String
    var transitOperator: String
    var transitServiceIdentifier: String
    var locationSelections: [EntryDetailLocationRole: EntryLocationSelection]
    var targetKind: LogKind
    var newPersonName = ""
    var newPlaceName = ""
    var newPlaceSystemImage: PlaceSystemImage = .mappin

    private var baseline: EntryDetailDraftBaseline

    init(entry: LogEntry) {
        let baseline = EntryDetailDraftBaseline(entry: entry)
        self.baseline = baseline
        startTime = baseline.startTime
        endTime = baseline.endTime
        startTimeZoneIdentifier = baseline.startTimeZoneIdentifier
        endTimeZoneIdentifier = baseline.endTimeZoneIdentifier
        selectedPeopleIDs = baseline.selectedPeopleIDs
        photoReferences = baseline.photoReferences
        transitType = baseline.transitType
        transitOperator = baseline.transitOperator
        transitServiceIdentifier = baseline.transitServiceIdentifier
        locationSelections = baseline.locationSelections
        targetKind = baseline.targetKind
    }

    func reload(from entry: LogEntry) {
        baseline = EntryDetailDraftBaseline(entry: entry)
        restoreAllDrafts()
    }

    func restoreDraft(for route: EntryDetailRoute) {
        switch route {
        case .time:
            startTime = baseline.startTime
            endTime = baseline.endTime
            startTimeZoneIdentifier = baseline.startTimeZoneIdentifier
            endTimeZoneIdentifier = baseline.endTimeZoneIdentifier
        case .people:
            selectedPeopleIDs = baseline.selectedPeopleIDs
        case .photos:
            photoReferences = baseline.photoReferences
        case .transitMetadata:
            transitType = baseline.transitType
            transitOperator = baseline.transitOperator
            transitServiceIdentifier = baseline.transitServiceIdentifier
        case .location(let role):
            restoreLocation(role)
        case .entryKind:
            targetKind = baseline.targetKind
        case .addPerson:
            newPersonName = ""
        case .addPlace:
            newPlaceName = ""
            newPlaceSystemImage = .mappin
        case .details, .locations, .advanced:
            break
        }
    }

    func isDirty(for route: EntryDetailRoute) -> Bool {
        switch route {
        case .time:
            startTime != baseline.startTime
                || endTime != baseline.endTime
                || startTimeZoneIdentifier != baseline.startTimeZoneIdentifier
                || endTimeZoneIdentifier != baseline.endTimeZoneIdentifier
        case .people:
            selectedPeopleIDs != baseline.selectedPeopleIDs
        case .photos:
            photoReferences != baseline.photoReferences
        case .transitMetadata:
            transitType != baseline.transitType
                || transitOperator != baseline.transitOperator
                || transitServiceIdentifier != baseline.transitServiceIdentifier
        case .location(let role):
            locationSelections[role] != baseline.locationSelections[role]
        case .entryKind:
            targetKind != baseline.targetKind
        case .addPerson:
            !newPersonName.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        case .addPlace:
            !newPlaceName.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty || newPlaceSystemImage != .mappin
        case .details, .locations, .advanced:
            false
        }
    }

    func selection(for role: EntryDetailLocationRole) -> EntryLocationSelection? {
        locationSelections[role]
    }

    func setSelection(
        _ selection: EntryLocationSelection,
        for role: EntryDetailLocationRole
    ) {
        locationSelections[role] = selection
        guard let zone = selection.location.timeZoneIdentifier else { return }
        switch role {
        case .place:
            startTimeZoneIdentifier = zone
            endTimeZoneIdentifier = zone
        case .origin:
            startTimeZoneIdentifier = zone
        case .destination:
            endTimeZoneIdentifier = zone
        }
    }

    private func restoreAllDrafts() {
        startTime = baseline.startTime
        endTime = baseline.endTime
        startTimeZoneIdentifier = baseline.startTimeZoneIdentifier
        endTimeZoneIdentifier = baseline.endTimeZoneIdentifier
        selectedPeopleIDs = baseline.selectedPeopleIDs
        photoReferences = baseline.photoReferences
        transitType = baseline.transitType
        transitOperator = baseline.transitOperator
        transitServiceIdentifier = baseline.transitServiceIdentifier
        locationSelections = baseline.locationSelections
        targetKind = baseline.targetKind
    }

    private func restoreLocation(_ role: EntryDetailLocationRole) {
        if let selection = baseline.locationSelections[role] {
            locationSelections[role] = selection
        } else {
            locationSelections.removeValue(forKey: role)
        }
        switch role {
        case .place:
            startTimeZoneIdentifier = baseline.startTimeZoneIdentifier
            endTimeZoneIdentifier = baseline.endTimeZoneIdentifier
        case .origin:
            startTimeZoneIdentifier = baseline.startTimeZoneIdentifier
        case .destination:
            endTimeZoneIdentifier = baseline.endTimeZoneIdentifier
        }
    }
}

private struct EntryDetailDraftBaseline {
    let startTime: Date
    let endTime: Date
    let startTimeZoneIdentifier: String
    let endTimeZoneIdentifier: String
    let selectedPeopleIDs: Set<UUID>
    let photoReferences: [PhotoReference]
    let transitType: String
    let transitOperator: String
    let transitServiceIdentifier: String
    let locationSelections: [EntryDetailLocationRole: EntryLocationSelection]
    let targetKind: LogKind

    init(entry: LogEntry) {
        let fallbackEnd = entry.endTime ?? .now
        let fallbackStart = entry.startTime
            ?? fallbackEnd.addingTimeInterval(-30 * 60)
        startTime = fallbackStart
        endTime = max(fallbackEnd, fallbackStart.addingTimeInterval(60))
        startTimeZoneIdentifier = entry.startTimeZoneIdentifier
        endTimeZoneIdentifier = entry.endTimeZoneIdentifier
        selectedPeopleIDs = Set(entry.people.map(\.id))
        photoReferences = entry.photoReferences
        transitType = entry.transitDetails?.type ?? ""
        transitOperator = entry.transitDetails?.sourceOrganizationName ?? ""
        transitServiceIdentifier =
            entry.transitDetails?.sourceServiceIdentifier ?? ""
        targetKind = entry.kind

        switch entry.kind {
        case .transit:
            locationSelections = [
                .origin: Self.selection(
                    place: entry.transitDetails?.originPlace,
                    location: entry.transitDetails?.originLocation,
                    fallbackTitle: "Origin"
                ),
                .destination: Self.selection(
                    place: entry.transitDetails?.destinationPlace,
                    location: entry.transitDetails?.destinationLocation,
                    fallbackTitle: "Destination"
                ),
            ].compactMapValues { $0 }
        case .placeVisit:
            locationSelections = [
                .place: Self.selection(
                    place: entry.placeVisitDetails?.place,
                    location: entry.placeVisitDetails?.location,
                    fallbackTitle: "Location"
                ),
            ].compactMapValues { $0 }
        case .workout:
            if entry.workoutDetails?.movementKind == .moving {
                locationSelections = [
                    .origin: Self.selection(
                        place: entry.workoutDetails?.originPlace,
                        location: entry.workoutDetails?.originLocation,
                        fallbackTitle: "Origin"
                    ),
                    .destination: Self.selection(
                        place: entry.workoutDetails?.destinationPlace,
                        location: entry.workoutDetails?.destinationLocation,
                        fallbackTitle: "Destination"
                    ),
                ].compactMapValues { $0 }
            } else {
                locationSelections = [
                    .place: Self.selection(
                        place: entry.workoutDetails?.place,
                        location: entry.workoutDetails?.sourceLocation,
                        fallbackTitle: "Location"
                    ),
                ].compactMapValues { $0 }
            }
        case .wakeUp:
            locationSelections = [:]
        }
    }

    private static func selection(
        place: Place?,
        location: Location?,
        fallbackTitle: String
    ) -> EntryLocationSelection? {
        if let place { return EntryLocationSelection(place: place) }
        guard let location else { return nil }
        return EntryLocationSelection(
            location: location,
            title: location.preferredName ?? fallbackTitle
        )
    }
}
