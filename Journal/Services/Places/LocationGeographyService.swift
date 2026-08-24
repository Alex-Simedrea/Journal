import Foundation
import SwiftData

actor LocationGeographyClient {
    static let shared = LocationGeographyClient()

    private var cache: [String: Location] = [:]
    private var tasks: [String: Task<Location, Never>] = [:]

    func enriched(_ location: Location) async -> Location {
        guard location.cityName == nil
                || location.countryName == nil
                || location.countryCode == nil else {
            return location
        }
        let key = String(
            format: "%.4f,%.4f",
            location.latitude,
            location.longitude
        )
        if let cached = cache[key] {
            return location.mergingGeography(from: cached)
        }
        if let task = tasks[key] {
            return location.mergingGeography(from: await task.value)
        }
        let coordinate = location.coordinate
        let task = Task<Location, Never> {
            await LocationService.shared.location(at: coordinate)
        }
        tasks[key] = task
        let resolved = await task.value
        cache[key] = resolved
        tasks[key] = nil
        return location.mergingGeography(from: resolved)
    }
}

@MainActor
enum LocationGeographyService {
    static func populateMissing(in modelContext: ModelContext) async {
        do {
            let placeIDs = try modelContext.fetch(FetchDescriptor<Place>())
                .map(\.id)
            let entryIDs = try modelContext.fetch(FetchDescriptor<LogEntry>())
                .map(\.id)
            var changed = false

            for placeID in placeIDs {
                guard let original = try placeLocation(
                    withID: placeID,
                    in: modelContext
                ), needsEnrichment(original) else { continue }
                let enriched = await LocationGeographyClient.shared.enriched(
                    original
                )
                guard enriched != original,
                      let place = try place(withID: placeID, in: modelContext),
                      place.location == original else { continue }
                place.location = enriched
                changed = true
            }

            for entryID in entryIDs {
                guard let original = try entrySnapshot(
                    withID: entryID,
                    in: modelContext
                ) else { continue }
                let enriched = await enrich(original)
                guard enriched != original,
                      let entry = try entry(withID: entryID, in: modelContext),
                      snapshot(for: entry) == original else { continue }
                apply(enriched, to: entry)
                changed = true
            }

            if changed { try modelContext.save() }
        } catch {
            // Geography is supplementary; partial summaries remain useful.
        }
    }

    private static func enrich(_ location: Location?) async -> Location? {
        guard let location, needsEnrichment(location) else { return location }
        return await LocationGeographyClient.shared.enriched(location)
    }

    private static func enrich(
        _ candidates: [LocationCandidate]
    ) async -> [LocationCandidate] {
        var result = candidates
        for index in result.indices {
            let location = result[index].location
            guard needsEnrichment(location) else { continue }
            let enriched = await LocationGeographyClient.shared.enriched(location)
            result[index].cityName = enriched.cityName
            result[index].countryName = enriched.countryName
            result[index].countryCode = enriched.countryCode
        }
        return result
    }

    private static func needsEnrichment(_ location: Location) -> Bool {
        location.cityName == nil
            || location.countryName == nil
            || location.countryCode == nil
    }

    private static func enrich(
        _ snapshot: EntryGeographySnapshot
    ) async -> EntryGeographySnapshot {
        EntryGeographySnapshot(
            transitOrigin: await enrich(snapshot.transitOrigin),
            transitDestination: await enrich(snapshot.transitDestination),
            transitOriginCandidates: await enrich(
                snapshot.transitOriginCandidates
            ),
            transitDestinationCandidates: await enrich(
                snapshot.transitDestinationCandidates
            ),
            visitLocation: await enrich(snapshot.visitLocation),
            visitCandidates: await enrich(snapshot.visitCandidates),
            workoutSource: await enrich(snapshot.workoutSource),
            workoutOrigin: await enrich(snapshot.workoutOrigin),
            workoutDestination: await enrich(snapshot.workoutDestination)
        )
    }

    private static func snapshot(for entry: LogEntry) -> EntryGeographySnapshot {
        EntryGeographySnapshot(
            transitOrigin: entry.transitDetails?.originLocation,
            transitDestination: entry.transitDetails?.destinationLocation,
            transitOriginCandidates: entry.transitDetails?.originCandidates
                ?? [],
            transitDestinationCandidates: entry.transitDetails?
                .destinationCandidates ?? [],
            visitLocation: entry.placeVisitDetails?.location,
            visitCandidates: entry.placeVisitDetails?.candidates ?? [],
            workoutSource: entry.workoutDetails?.sourceLocation,
            workoutOrigin: entry.workoutDetails?.originLocation,
            workoutDestination: entry.workoutDetails?.destinationLocation
        )
    }

    private static func apply(
        _ snapshot: EntryGeographySnapshot,
        to entry: LogEntry
    ) {
        if let details = entry.transitDetails {
            details.originLocation = snapshot.transitOrigin
            details.destinationLocation = snapshot.transitDestination
            details.originCandidates = snapshot.transitOriginCandidates
            details.destinationCandidates = snapshot.transitDestinationCandidates
        }
        if let details = entry.placeVisitDetails {
            details.location = snapshot.visitLocation
            details.candidates = snapshot.visitCandidates
        }
        if let details = entry.workoutDetails {
            details.sourceLocation = snapshot.workoutSource
            details.originLocation = snapshot.workoutOrigin
            details.destinationLocation = snapshot.workoutDestination
        }
    }

    private static func placeLocation(
        withID id: UUID,
        in modelContext: ModelContext
    ) throws -> Location? {
        try place(withID: id, in: modelContext)?.location
    }

    private static func place(
        withID id: UUID,
        in modelContext: ModelContext
    ) throws -> Place? {
        var descriptor = FetchDescriptor<Place>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func entrySnapshot(
        withID id: UUID,
        in modelContext: ModelContext
    ) throws -> EntryGeographySnapshot? {
        try entry(withID: id, in: modelContext).map(snapshot(for:))
    }

    private static func entry(
        withID id: UUID,
        in modelContext: ModelContext
    ) throws -> LogEntry? {
        var descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

private struct EntryGeographySnapshot: Equatable {
    let transitOrigin: Location?
    let transitDestination: Location?
    let transitOriginCandidates: [LocationCandidate]
    let transitDestinationCandidates: [LocationCandidate]
    let visitLocation: Location?
    let visitCandidates: [LocationCandidate]
    let workoutSource: Location?
    let workoutOrigin: Location?
    let workoutDestination: Location?
}

nonisolated private extension Location {
    func mergingGeography(from resolved: Location) -> Location {
        var copy = self
        copy.cityName = cityName ?? resolved.cityName
        copy.countryName = countryName ?? resolved.countryName
        copy.countryCode = countryCode ?? resolved.countryCode
        copy.formattedAddress = formattedAddress ?? resolved.formattedAddress
        copy.compactAddress = compactAddress ?? resolved.compactAddress
        copy.timeZoneIdentifier = timeZoneIdentifier
            ?? resolved.timeZoneIdentifier
        return copy
    }
}
