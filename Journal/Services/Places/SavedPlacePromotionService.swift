//
//  SavedPlacePromotionService.swift
//  Journal
//

import CoreLocation
import Foundation
import SwiftData

enum EntryLocationAssociationSlot: String {
    case transitOrigin
    case transitDestination
    case visit
    case workoutPlace
    case workoutOrigin
    case workoutDestination

    var title: LocalizedStringResource {
        switch self {
        case .transitOrigin: "Transit origin"
        case .transitDestination: "Transit destination"
        case .visit: "Place visit"
        case .workoutPlace: "Workout location"
        case .workoutOrigin: "Workout origin"
        case .workoutDestination: "Workout destination"
        }
    }
}

struct EntryLocationAssociationMatch: Identifiable {
    let entryID: UUID
    let entryDate: Date
    let slot: EntryLocationAssociationSlot
    let location: Location
    let associatedPlaceID: UUID?

    var id: String { "\(entryID.uuidString)-\(slot.rawValue)" }

    init(entry: LogEntry, slot: EntryLocationAssociationSlot, location: Location) {
        entryID = entry.id
        entryDate = entry.startTime ?? entry.createdAt
        self.slot = slot
        self.location = location
        associatedPlaceID = switch slot {
        case .transitOrigin: entry.transitDetails?.originPlace?.id
        case .transitDestination: entry.transitDetails?.destinationPlace?.id
        case .visit: entry.placeVisitDetails?.place?.id
        case .workoutPlace: entry.workoutDetails?.place?.id
        case .workoutOrigin: entry.workoutDetails?.originPlace?.id
        case .workoutDestination: entry.workoutDetails?.destinationPlace?.id
        }
    }
}

@MainActor
enum SavedPlacePromotionService {
    static func matches(
        for place: Place,
        in modelContext: ModelContext
    ) throws -> [EntryLocationAssociationMatch] {
        let entries = try modelContext.fetch(
            FetchDescriptor<LogEntry>(
                sortBy: [SortDescriptor(\LogEntry.startTime)]
            )
        )
        return entries.flatMap(locationMatches)
            .filter { match in
                isSameLocation(match.location, place.location, place: place)
                    && match.associatedPlaceID != place.id
            }
    }

    static func apply(
        _ matches: [EntryLocationAssociationMatch],
        to place: Place,
        in modelContext: ModelContext
    ) throws {
        guard place.modelContext === modelContext, !place.isDeleted else { return }
        let entriesByID = Dictionary(try modelContext.fetch(FetchDescriptor<LogEntry>()).map {
            ($0.id, $0)
        }, uniquingKeysWith: { first, _ in first })
        for match in matches {
            guard let entry = entriesByID[match.entryID],
                  let current = locationMatches(in: entry).first(where: { $0.slot == match.slot }),
                  current.location == match.location,
                  current.associatedPlaceID == match.associatedPlaceID else { continue }
            switch match.slot {
            case .transitOrigin:
                entry.transitDetails?.originPlace = place
                entry.transitDetails?.fieldReviews.removeAll { $0.field == .origin }
            case .transitDestination:
                entry.transitDetails?.destinationPlace = place
                entry.transitDetails?.fieldReviews.removeAll { $0.field == .destination }
            case .visit:
                entry.placeVisitDetails?.place = place
                entry.placeVisitDetails?.fieldReviews.removeAll { $0.field == .place }
            case .workoutPlace:
                entry.workoutDetails?.place = place
                entry.workoutDetails?.placeResolutionSource = .manual
                entry.workoutDetails?.fieldReviews.removeAll { $0.field == .place }
            case .workoutOrigin:
                entry.workoutDetails?.originPlace = place
                entry.workoutDetails?.originResolutionSource = .manual
                entry.workoutDetails?.fieldReviews.removeAll { $0.field == .origin }
            case .workoutDestination:
                entry.workoutDetails?.destinationPlace = place
                entry.workoutDetails?.destinationResolutionSource = .manual
                entry.workoutDetails?.fieldReviews.removeAll { $0.field == .destination }
            }
            synchronizeReviewState(entry)
        }
        try JournalPersistence.save(modelContext)
    }

    private static func locationMatches(
        in entry: LogEntry
    ) -> [EntryLocationAssociationMatch] {
        var matches: [EntryLocationAssociationMatch] = []
        if let details = entry.transitDetails {
            if let location = details.originLocation {
                matches.append(.init(entry: entry, slot: .transitOrigin, location: location))
            }
            if let location = details.destinationLocation {
                matches.append(.init(entry: entry, slot: .transitDestination, location: location))
            }
        }
        if let details = entry.placeVisitDetails, let location = details.location {
            matches.append(.init(entry: entry, slot: .visit, location: location))
        }
        if let details = entry.workoutDetails {
            if let location = details.sourceLocation {
                matches.append(.init(entry: entry, slot: .workoutPlace, location: location))
            }
            if let location = details.originLocation {
                matches.append(.init(entry: entry, slot: .workoutOrigin, location: location))
            }
            if let location = details.destinationLocation {
                matches.append(.init(entry: entry, slot: .workoutDestination, location: location))
            }
        }
        return matches
    }

    private static func isSameLocation(
        _ lhs: Location,
        _ rhs: Location,
        place: Place
    ) -> Bool {
        let distance = CLLocation(
            latitude: lhs.latitude,
            longitude: lhs.longitude
        ).distance(
            from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        )
        if distance <= max(50, place.accuracyRadiusMeters) { return true }

        guard let leftAddress = normalized(lhs.formattedAddress),
              let rightAddress = normalized(rhs.formattedAddress) else {
            return false
        }
        return leftAddress == rightAddress
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func synchronizeReviewState(_ entry: LogEntry) {
        let hasFieldReviews: Bool = switch entry.kind {
        case .transit: !(entry.transitDetails?.fieldReviews.isEmpty ?? true)
        case .placeVisit: !(entry.placeVisitDetails?.fieldReviews.isEmpty ?? true)
        case .workout: !(entry.workoutDetails?.fieldReviews.isEmpty ?? true)
        case .wakeUp: false
        }
        entry.needsReview = entry.entryKindReviewReason != nil || hasFieldReviews
    }
}
