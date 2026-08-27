import CoreLocation
import Foundation
import SwiftData

nonisolated enum TimelineTransitGapInference {
    static let minimumDistanceMeters: CLLocationDistance = 1
    static let maximumWalkingDistanceMeters: CLLocationDistance = 5_000
    static let maximumWalkingSpeedMetersPerSecond = 2.5

    static func transitType(
        distanceMeters: CLLocationDistance,
        duration: TimeInterval
    ) -> String {
        guard duration > 0 else { return "Car" }
        let requiredSpeed = distanceMeters / duration
        return distanceMeters <= maximumWalkingDistanceMeters
            && requiredSpeed <= maximumWalkingSpeedMetersPerSecond
            ? "Walk"
            : "Car"
    }
}

@MainActor
enum TimelineTransitGapService {
    static func makeDraft(
        gapID: TimelineTransitGapID,
        in modelContext: ModelContext
    ) throws -> LogEntry {
        let gap = try resolvedGap(gapID: gapID, in: modelContext)
        guard try !containsTransit(
            from: gap.startTime,
            to: gap.endTime,
            in: modelContext
        ) else {
            throw TimelineTransitGapError.conflictingTransit
        }

        let originPeopleIDs = Set(gap.originEntry.people.map(\.id))
        let sharedPeople = gap.destinationEntry.people.filter {
            originPeopleIDs.contains($0.id)
        }.map(detachedPerson)
        let transitType = TimelineTransitGapInference.transitType(
            distanceMeters: gap.distance,
            duration: gap.endTime.timeIntervalSince(gap.startTime)
        )
        let draft = ResolvedTransitDraft(
            transitType: transitType,
            originPlace: gap.originDetails.place,
            originLocation: gap.originLocation,
            originRawText: gap.originDetails.place?.name
                ?? gap.originLocation.preferredName,
            destinationPlace: gap.destinationDetails.place,
            destinationLocation: gap.destinationLocation,
            destinationRawText: gap.destinationDetails.place?.name
                ?? gap.destinationLocation.preferredName,
            startTime: gap.startTime,
            endTime: gap.endTime,
            timeConfidence: .inferredFromHistory,
            people: sharedPeople,
            durationSource: .unresolved,
            originCandidates: [],
            destinationCandidates: [],
            unresolvedPeople: [],
            fieldReviews: []
        )
        let entry = TransitEntryStore.makeEntry(draft: draft, rawInput: nil)
        entry.startTimeZoneIdentifier = gap.originEntry.endTimeZoneIdentifier
        entry.endTimeZoneIdentifier = gap.destinationEntry.startTimeZoneIdentifier
        return entry
    }

    @discardableResult
    static func insert(
        _ draft: LogEntry,
        selectedPeopleIDs: Set<UUID>,
        gapID: TimelineTransitGapID,
        in modelContext: ModelContext
    ) throws -> UUID {
        _ = try resolvedGap(gapID: gapID, in: modelContext)
        guard draft.kind == .transit,
              draft.transitDetails != nil,
              let startTime = draft.startTime,
              let endTime = draft.endTime,
              endTime > startTime else {
            throw TimelineTransitGapError.invalidDraft
        }
        guard try !containsTransit(
            from: startTime,
            to: endTime,
            in: modelContext
        ) else {
            throw TimelineTransitGapError.conflictingTransit
        }

        draft.people = try modelContext.fetch(FetchDescriptor<Person>())
            .filter { selectedPeopleIDs.contains($0.id) }
        try TransitEntryStore.insert(
            draft,
            refreshDistance: false,
            in: modelContext
        )
        return draft.id
    }

    private static func resolvedGap(
        gapID: TimelineTransitGapID,
        in modelContext: ModelContext
    ) throws -> ResolvedTimelineTransitGap {
        guard let originEntry = try entry(
            withID: gapID.originVisitEntryID,
            in: modelContext
        ),
        let destinationEntry = try entry(
            withID: gapID.destinationVisitEntryID,
            in: modelContext
        ),
        originEntry.kind == .placeVisit,
        destinationEntry.kind == .placeVisit,
        let startTime = originEntry.endTime,
        let endTime = destinationEntry.startTime,
        endTime > startTime,
        let originDetails = originEntry.placeVisitDetails,
        let destinationDetails = destinationEntry.placeVisitDetails,
        let originLocation = originDetails.location
            ?? originDetails.place?.location,
        let destinationLocation = destinationDetails.location
            ?? destinationDetails.place?.location else {
            throw TimelineTransitGapError.gapUnavailable
        }

        let distance = CLLocation(
            latitude: originLocation.latitude,
            longitude: originLocation.longitude
        ).distance(
            from: CLLocation(
                latitude: destinationLocation.latitude,
                longitude: destinationLocation.longitude
            )
        )
        guard distance >= TimelineTransitGapInference.minimumDistanceMeters
        else {
            throw TimelineTransitGapError.locationsTooClose
        }
        return ResolvedTimelineTransitGap(
            originEntry: originEntry,
            destinationEntry: destinationEntry,
            originDetails: originDetails,
            destinationDetails: destinationDetails,
            originLocation: originLocation,
            destinationLocation: destinationLocation,
            startTime: startTime,
            endTime: endTime,
            distance: distance
        )
    }

    private static func containsTransit(
        from startTime: Date,
        to endTime: Date,
        in modelContext: ModelContext
    ) throws -> Bool {
        try modelContext.fetch(FetchDescriptor<LogEntry>()).contains { entry in
            guard entry.kind == .transit,
                  let entryStart = entry.startTime,
                  let entryEnd = entry.endTime else {
                return false
            }
            return entryStart < endTime && entryEnd > startTime
        }
    }

    private static func entry(
        withID entryID: UUID,
        in modelContext: ModelContext
    ) throws -> LogEntry? {
        var descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.id == entryID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func detachedPerson(_ person: Person) -> Person {
        Person(
            id: person.id,
            name: person.name,
            aliases: person.aliases,
            contactIdentifier: person.contactIdentifier,
            firstMetAt: person.firstMetAt,
            lastMetAt: person.lastMetAt
        )
    }
}

@MainActor
private struct ResolvedTimelineTransitGap {
    let originEntry: LogEntry
    let destinationEntry: LogEntry
    let originDetails: PlaceVisitDetails
    let destinationDetails: PlaceVisitDetails
    let originLocation: Location
    let destinationLocation: Location
    let startTime: Date
    let endTime: Date
    let distance: CLLocationDistance
}

private enum TimelineTransitGapError: LocalizedError {
    case gapUnavailable
    case locationsTooClose
    case conflictingTransit
    case invalidDraft

    var errorDescription: String? {
        switch self {
        case .gapUnavailable:
            String(localized: "The visits no longer form an available transit gap.")
        case .locationsTooClose:
            String(localized: "The two visits are too close to create a transit entry.")
        case .conflictingTransit:
            String(localized: "Another transit entry already overlaps this time.")
        case .invalidDraft:
            String(localized: "The transit needs valid times, locations, and a type before it can be added.")
        }
    }
}
