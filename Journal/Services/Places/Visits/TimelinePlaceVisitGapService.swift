import Foundation
import SwiftData

nonisolated struct TimelinePlaceVisitGapID: Hashable, Identifiable, Sendable {
    let arrivalEntryID: UUID
    let departureEntryID: UUID

    var id: Self { self }
}

nonisolated enum TimelinePlaceVisitGapInference {
    static let minimumDuration: TimeInterval = 5 * 60

    static func gapID(
        after arrival: TimelineEntrySnapshot,
        before departure: TimelineEntrySnapshot,
        entries: [TimelineEntrySnapshot]
    ) -> TimelinePlaceVisitGapID? {
        guard arrival.id != departure.id,
            arrival.usesCompactMovementPresentation,
            departure.usesCompactMovementPresentation,
            let start = arrival.endTime,
            let end = departure.startTime,
            end.timeIntervalSince(start) > minimumDuration,
            let destination = arrival.kind == .workout
                ? arrival.workoutDestinationLocation
                : arrival.destinationLocation,
            let origin = departure.kind == .workout
                ? departure.workoutOriginLocation : departure.originLocation,
            !GuidedComposerLocationRanking.isHomeName(destination.name),
            !GuidedComposerLocationRanking.isHomeName(origin.name),
            destination.hasCoordinate,
            origin.hasCoordinate,
            TimelineBoundaryMatcher.locationsMatch(destination, origin),
            !entries.contains(where: { entry in
                guard entry.id != arrival.id, entry.id != departure.id,
                    entry.kind != .wakeUp,
                    let entryStart = entry.startTime,
                    let entryEnd = entry.endTime
                else { return false }
                return entryStart < end && entryEnd > start
            })
        else { return nil }

        return TimelinePlaceVisitGapID(
            arrivalEntryID: arrival.id,
            departureEntryID: departure.id
        )
    }
}

@MainActor
enum TimelinePlaceVisitGapService {
    static func makeDraft(
        gapID: TimelinePlaceVisitGapID,
        in modelContext: ModelContext
    ) throws -> LogEntry {
        let (arrival, departure) = try resolve(gapID, in: modelContext)
        let destinationPlace =
            arrival.kind == .workout
            ? arrival.workoutDetails?.destinationPlace
            : arrival.transitDetails?.destinationPlace
        let originPlace =
            departure.kind == .workout
            ? departure.workoutDetails?.originPlace
            : departure.transitDetails?.originPlace
        let place = destinationPlace ?? originPlace
        let snapshot = TimelineEntrySnapshot(entry: arrival)
        let endpoint =
            arrival.kind == .workout
            ? snapshot.workoutDestinationLocation : snapshot.destinationLocation
        let storedLocation =
            arrival.kind == .workout
            ? arrival.workoutDetails?.destinationLocation
            : arrival.transitDetails?.destinationLocation
        let location =
            storedLocation ?? place?.location
            ?? endpoint.map {
                Location(
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    displayName: $0.name,
                    systemImage: $0.systemImage,
                    timeZoneIdentifier: arrival.endTimeZoneIdentifier,
                    cityName: $0.cityName,
                    countryName: $0.countryName,
                    countryCode: $0.countryCode
                )
            }
        let arrivalPeople = Set(arrival.people.map(\.id))
        let people = departure.people.filter { arrivalPeople.contains($0.id) }
            .map { person in
                Person(
                    id: person.id,
                    name: person.name,
                    aliases: person.aliases,
                    contactIdentifier: person.contactIdentifier,
                    firstMetAt: person.firstMetAt,
                    lastMetAt: person.lastMetAt
                )
            }
        let draft = PlaceVisitEntryStore.makeEntry(
            draft: ResolvedPlaceVisitDraft(
                place: place,
                location: location,
                placeRawText: place?.name ?? endpoint?.name,
                startTime: arrival.endTime,
                endTime: departure.startTime,
                timeConfidence: .inferredFromHistory,
                people: people,
                candidates: [],
                unresolvedPeople: [],
                fieldReviews: [],
                entryKindReviewReason: nil
            ),
            rawInput: nil
        )
        draft.startTimeZoneIdentifier = arrival.endTimeZoneIdentifier
        draft.endTimeZoneIdentifier = departure.startTimeZoneIdentifier
        return draft
    }

    @discardableResult
    static func insert(
        _ draft: LogEntry,
        selectedPeopleIDs: Set<UUID>,
        gapID: TimelinePlaceVisitGapID,
        in modelContext: ModelContext
    ) throws -> UUID {
        let (arrival, departure) = try resolve(gapID, in: modelContext)
        guard draft.kind == .placeVisit,
            let details = draft.placeVisitDetails,
            details.location != nil || details.place != nil,
            let start = draft.startTime,
            let end = draft.endTime,
            end > start,
            let gapStart = arrival.endTime,
            let gapEnd = departure.startTime,
            start >= gapStart, end <= gapEnd
        else {
            throw TimelinePlaceVisitGapError.invalidDraft
        }
        draft.people = try modelContext.fetch(FetchDescriptor<Person>())
            .filter { selectedPeopleIDs.contains($0.id) }
        try PlaceVisitEntryStore.insert(draft, in: modelContext)
        TimelineDataChange.post(.structure)
        return draft.id
    }

    private static func resolve(
        _ gapID: TimelinePlaceVisitGapID,
        in modelContext: ModelContext
    ) throws -> (LogEntry, LogEntry) {
        let entries = try modelContext.fetch(FetchDescriptor<LogEntry>())
        guard
            let arrival = entries.first(where: { $0.id == gapID.arrivalEntryID }
            ),
            let departure = entries.first(where: {
                $0.id == gapID.departureEntryID
            }),
            TimelinePlaceVisitGapInference.gapID(
                after: TimelineEntrySnapshot(entry: arrival),
                before: TimelineEntrySnapshot(entry: departure),
                entries: entries.map { TimelineEntrySnapshot(entry: $0) }
            ) == gapID
        else {
            throw TimelinePlaceVisitGapError.gapUnavailable
        }
        return (arrival, departure)
    }
}

private enum TimelinePlaceVisitGapError: LocalizedError {
    case gapUnavailable
    case invalidDraft

    var errorDescription: String? {
        switch self {
        case .gapUnavailable:
            String(
                localized:
                    "These entries no longer leave an empty visit of more than five minutes at the same place."
            )
        case .invalidDraft:
            String(
                localized:
                    "Choose a place and an end time after the start time, within the arrival and departure times."
            )
        }
    }
}
