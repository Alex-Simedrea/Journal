//
//  EntryDetailEditingService.swift
//  Journal
//

import Foundation
import SwiftData

@MainActor
enum EntryDetailEditingService {
    static func createPerson(
        name: String,
        in modelContext: ModelContext
    ) throws -> Person {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw EntryDetailEditingError.missingName
        }
        let person = Person(name: trimmedName)
        modelContext.insert(person)
        try save(modelContext)
        return person
    }

    static func createPlace(
        name: String,
        selection: EntryLocationSelection,
        systemImage: PlaceSystemImage,
        in modelContext: ModelContext
    ) throws -> Place {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw EntryDetailEditingError.missingName
        }
        let place = Place(
            name: trimmedName,
            location: selection.location.withFallbackDisplayName(trimmedName),
            systemImage: systemImage
        )
        modelContext.insert(place)
        try save(modelContext)
        return place
    }

    static func saveTime(
        entry: LogEntry,
        session: EntryDetailEditSession,
        in modelContext: ModelContext
    ) throws {
        guard entry.kind != .workout,
              session.endTime > session.startTime else {
            throw EntryDetailEditingError.invalidTimeRange
        }

        entry.startTime = session.startTime
        entry.endTime = session.endTime
        entry.startTimeZoneIdentifier = session.startTimeZoneIdentifier
        entry.endTimeZoneIdentifier = session.endTimeZoneIdentifier
        entry.timeConfidence = .manualOverride
        entry.transitDetails?.durationSource = .manualOverride
        removeTimeReview(from: entry)
        entry.weather = nil
        entry.endWeather = nil
        updateNeedsReview(entry)
        try save(modelContext)
        EntryWeatherService.refreshInBackground(entry, in: modelContext)
    }

    static func savePeople(
        entry: LogEntry,
        session: EntryDetailEditSession,
        people: [Person],
        in modelContext: ModelContext
    ) throws {
        entry.people = people.filter {
            session.selectedPeopleIDs.contains($0.id)
        }
        switch entry.kind {
        case .transit:
            entry.transitDetails?.unresolvedPeople = []
            entry.transitDetails?.fieldReviews.removeAll { $0.field == .people }
        case .placeVisit:
            entry.placeVisitDetails?.unresolvedPeople = []
            entry.placeVisitDetails?.fieldReviews.removeAll { $0.field == .people }
        case .workout, .wakeUp:
            break
        }
        updateNeedsReview(entry)
        try save(modelContext)
    }

    static func savePhotos(
        entry: LogEntry,
        session: EntryDetailEditSession,
        in modelContext: ModelContext
    ) throws {
        entry.photoReferences = session.photoReferences
        try save(modelContext)
    }

    static func saveTransitMetadata(
        entry: LogEntry,
        session: EntryDetailEditSession,
        in modelContext: ModelContext
    ) throws {
        guard let details = entry.transitDetails,
              !session.transitType.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty else {
            throw EntryDetailEditingError.missingTransitType
        }
        let previousType = details.type
        details.type = session.transitType
        details.sourceOrganizationName = session.transitOperator.nilIfBlank
        details.sourceServiceIdentifier =
            session.transitServiceIdentifier.nilIfBlank
        details.fieldReviews.removeAll { $0.field == .transitType }
        updateNeedsReview(entry)
        try save(modelContext)
        if previousType != details.type {
            TransitDistanceService.refreshInBackground(entry, in: modelContext)
        }
    }

    static func saveLocation(
        entry: LogEntry,
        role: EntryDetailLocationRole,
        session: EntryDetailEditSession,
        places: [Place],
        in modelContext: ModelContext
    ) throws {
        guard let selection = session.selection(for: role) else {
            throw EntryDetailEditingError.missingLocation
        }
        let place = places.first { $0.id == selection.placeID }

        switch entry.kind {
        case .transit:
            try saveTransitLocation(
                entry: entry,
                role: role,
                selection: selection,
                place: place
            )
        case .placeVisit:
            guard role == .place,
                  let details = entry.placeVisitDetails else {
                throw EntryDetailEditingError.missingLocation
            }
            details.place = place
            details.location = selection.location.withFallbackDisplayName(
                place?.name ?? selection.title
            )
            details.placeRawText = place?.name ?? selection.title
            details.candidates = []
            details.fieldReviews.removeAll { $0.field == .place }
            let zone = selection.location.timeZoneIdentifier
                ?? entry.creationTimeZoneIdentifier
            entry.startTimeZoneIdentifier = zone
            entry.endTimeZoneIdentifier = zone
            entry.weather = nil
            entry.endWeather = nil
        case .workout:
            guard let place,
                  let details = entry.workoutDetails else {
                throw EntryDetailEditingError.workoutRequiresSavedPlace
            }
            switch role {
            case .place:
                details.place = place
                details.placeResolutionSource = .manual
                details.fieldReviews.removeAll { $0.field == .place }
            case .origin:
                details.originPlace = place
                details.originResolutionSource = .manual
                details.fieldReviews.removeAll { $0.field == .origin }
            case .destination:
                details.destinationPlace = place
                details.destinationResolutionSource = .manual
                details.fieldReviews.removeAll { $0.field == .destination }
            }
        case .wakeUp:
            throw EntryDetailEditingError.unsupportedEntryKind
        }

        updateNeedsReview(entry)
        try save(modelContext)

        if entry.kind == .transit {
            TransitDistanceService.refreshInBackground(entry, in: modelContext)
        }
        if entry.kind != .workout {
            EntryWeatherService.refreshInBackground(entry, in: modelContext)
        }
    }

    static func convertKind(
        entry: LogEntry,
        session: EntryDetailEditSession,
        places: [Place],
        in modelContext: ModelContext
    ) throws {
        guard entry.entryKindReviewReason != nil,
              session.targetKind != entry.kind else {
            throw EntryDetailEditingError.unsupportedEntryKind
        }

        switch (entry.kind, session.targetKind) {
        case (.transit, .placeVisit):
            let selection = session.selection(for: .destination)
                ?? session.selection(for: .origin)
            let place = places.first { $0.id == selection?.placeID }
            let oldDetails = entry.transitDetails
            entry.transitDetails = nil
            if let oldDetails { modelContext.delete(oldDetails) }
            let reviews = selection == nil
                ? [PlaceVisitFieldReview(
                    field: .place,
                    reason: String(localized: "Choose the visited place.")
                )]
                : []
            entry.placeVisitDetails = PlaceVisitDetails(
                place: place,
                location: selection?.location,
                placeRawText: place?.name ?? selection?.title,
                fieldReviews: reviews
            )
            entry.kind = .placeVisit
        case (.placeVisit, .transit):
            let oldDetails = entry.placeVisitDetails
            entry.placeVisitDetails = nil
            if let oldDetails { modelContext.delete(oldDetails) }
            entry.transitDetails = TransitDetails(
                type: session.transitType.isEmpty
                    ? "Transit"
                    : session.transitType,
                durationSource: .manualOverride,
                fieldReviews: [
                    TransitFieldReview(
                        field: .origin,
                        reason: String(localized: "Choose the origin.")
                    ),
                    TransitFieldReview(
                        field: .destination,
                        reason: String(localized: "Choose the destination.")
                    ),
                ]
            )
            entry.kind = .transit
        default:
            throw EntryDetailEditingError.unsupportedEntryKind
        }

        entry.entryKindReviewReason = nil
        entry.weather = nil
        entry.endWeather = nil
        updateNeedsReview(entry)
        try save(modelContext)
        EntryWeatherService.refreshInBackground(entry, in: modelContext)
    }

    static func updateNeedsReview(_ entry: LogEntry) {
        let hasFieldReviews: Bool = switch entry.kind {
        case .transit:
            !(entry.transitDetails?.fieldReviews.isEmpty ?? true)
        case .placeVisit:
            !(entry.placeVisitDetails?.fieldReviews.isEmpty ?? true)
        case .workout:
            !(entry.workoutDetails?.fieldReviews.isEmpty ?? true)
        case .wakeUp:
            false
        }
        entry.needsReview = entry.entryKindReviewReason != nil || hasFieldReviews
    }

    private static func saveTransitLocation(
        entry: LogEntry,
        role: EntryDetailLocationRole,
        selection: EntryLocationSelection,
        place: Place?
    ) throws {
        guard let details = entry.transitDetails else {
            throw EntryDetailEditingError.missingLocation
        }
        switch role {
        case .origin:
            details.originPlace = place
            details.originLocation = selection.location.withFallbackDisplayName(
                place?.name ?? selection.title
            )
            details.originRawText = place?.name ?? selection.title
            details.originCandidates = []
            details.fieldReviews.removeAll { $0.field == .origin }
            entry.startTimeZoneIdentifier =
                selection.location.timeZoneIdentifier
                ?? entry.creationTimeZoneIdentifier
            entry.weather = nil
        case .destination:
            details.destinationPlace = place
            details.destinationLocation =
                selection.location.withFallbackDisplayName(
                    place?.name ?? selection.title
                )
            details.destinationRawText = place?.name ?? selection.title
            details.destinationCandidates = []
            details.fieldReviews.removeAll { $0.field == .destination }
            entry.endTimeZoneIdentifier = selection.location.timeZoneIdentifier
                ?? entry.creationTimeZoneIdentifier
            entry.endWeather = nil
        case .place:
            throw EntryDetailEditingError.missingLocation
        }
    }

    private static func removeTimeReview(from entry: LogEntry) {
        switch entry.kind {
        case .transit:
            entry.transitDetails?.fieldReviews.removeAll { $0.field == .time }
        case .placeVisit:
            entry.placeVisitDetails?.fieldReviews.removeAll { $0.field == .time }
        case .workout, .wakeUp:
            break
        }
    }

    private static func save(_ modelContext: ModelContext) throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

enum EntryDetailEditingError: LocalizedError {
    case missingName
    case invalidTimeRange
    case missingTransitType
    case missingLocation
    case workoutRequiresSavedPlace
    case unsupportedEntryKind

    var errorDescription: String? {
        switch self {
        case .missingName:
            "Enter a name before saving."
        case .invalidTimeRange:
            "The end time must be later than the start time."
        case .missingTransitType:
            "Choose a transit type before saving."
        case .missingLocation:
            "Choose a location before saving."
        case .workoutRequiresSavedPlace:
            "Save this location as a Place before associating it with a workout."
        case .unsupportedEntryKind:
            "This entry type cannot be edited here."
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
