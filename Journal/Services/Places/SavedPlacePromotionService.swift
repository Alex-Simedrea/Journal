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
    let entry: LogEntry
    let slot: EntryLocationAssociationSlot
    let location: Location

    var id: String { "\(entry.id.uuidString)-\(slot.rawValue)" }
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
                    && existingPlace(for: match)?.id != place.id
            }
    }

    static func apply(
        _ matches: [EntryLocationAssociationMatch],
        to place: Place,
        in modelContext: ModelContext
    ) throws {
        for match in matches {
            switch match.slot {
            case .transitOrigin:
                match.entry.transitDetails?.originPlace = place
                match.entry.transitDetails?.fieldReviews.removeAll { $0.field == .origin }
            case .transitDestination:
                match.entry.transitDetails?.destinationPlace = place
                match.entry.transitDetails?.fieldReviews.removeAll { $0.field == .destination }
            case .visit:
                match.entry.placeVisitDetails?.place = place
                match.entry.placeVisitDetails?.fieldReviews.removeAll { $0.field == .place }
            case .workoutPlace:
                match.entry.workoutDetails?.place = place
                match.entry.workoutDetails?.placeResolutionSource = .manual
                match.entry.workoutDetails?.fieldReviews.removeAll { $0.field == .place }
            case .workoutOrigin:
                match.entry.workoutDetails?.originPlace = place
                match.entry.workoutDetails?.originResolutionSource = .manual
                match.entry.workoutDetails?.fieldReviews.removeAll { $0.field == .origin }
            case .workoutDestination:
                match.entry.workoutDetails?.destinationPlace = place
                match.entry.workoutDetails?.destinationResolutionSource = .manual
                match.entry.workoutDetails?.fieldReviews.removeAll { $0.field == .destination }
            }
            synchronizeReviewState(match.entry)
        }
        try modelContext.save()
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

    private static func existingPlace(
        for match: EntryLocationAssociationMatch
    ) -> Place? {
        switch match.slot {
        case .transitOrigin: match.entry.transitDetails?.originPlace
        case .transitDestination: match.entry.transitDetails?.destinationPlace
        case .visit: match.entry.placeVisitDetails?.place
        case .workoutPlace: match.entry.workoutDetails?.place
        case .workoutOrigin: match.entry.workoutDetails?.originPlace
        case .workoutDestination: match.entry.workoutDetails?.destinationPlace
        }
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
