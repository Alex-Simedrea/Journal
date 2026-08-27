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

nonisolated enum LocationGeographyService {
    static func populateMissing(in modelContext: ModelContext) async {
        do {
            let placeTargets = try modelContext.fetch(FetchDescriptor<Place>())
                .compactMap { place -> PlaceGeographyTarget? in
                    guard needsEnrichment(place.location) else { return nil }
                    return PlaceGeographyTarget(
                        id: place.id,
                        original: place.location
                    )
                }
            let entryTargets = try modelContext.fetch(
                FetchDescriptor<LogEntry>()
            ).compactMap { entry -> EntryGeographyTarget? in
                let original = snapshot(for: entry)
                return original.needsEnrichment
                    ? EntryGeographyTarget(id: entry.id, original: original)
                    : nil
            }

            var placeUpdates: [PlaceGeographyUpdate] = []
            for target in placeTargets {
                let enriched = await LocationGeographyClient.shared.enriched(
                    target.original
                )
                guard enriched != target.original else { continue }
                placeUpdates.append(.init(
                    id: target.id,
                    original: target.original,
                    enriched: enriched
                ))
            }

            var entryUpdates: [EntryGeographyUpdate] = []
            for target in entryTargets {
                let enriched = await enrich(target.original)
                guard enriched != target.original else { continue }
                entryUpdates.append(.init(
                    id: target.id,
                    original: target.original,
                    enriched: enriched
                ))
            }

            guard !placeUpdates.isEmpty || !entryUpdates.isEmpty else { return }
            let placesByID = Dictionary(uniqueKeysWithValues: try modelContext
                .fetch(FetchDescriptor<Place>()).map { ($0.id, $0) })
            let entriesByID = Dictionary(uniqueKeysWithValues: try modelContext
                .fetch(FetchDescriptor<LogEntry>()).map { ($0.id, $0) })
            var changed = false
            for update in placeUpdates {
                guard let place = placesByID[update.id],
                      place.location == update.original else { continue }
                place.location = update.enriched
                changed = true
            }
            for update in entryUpdates {
                guard let entry = entriesByID[update.id],
                      snapshot(for: entry) == update.original else { continue }
                apply(update.enriched, to: entry)
                changed = true
            }
            guard changed else { return }
            try modelContext.save()
            await TimelineDataChange.post()
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

}

nonisolated private struct PlaceGeographyTarget: Sendable {
    let id: UUID
    let original: Location
}

nonisolated private struct PlaceGeographyUpdate: Sendable {
    let id: UUID
    let original: Location
    let enriched: Location
}

nonisolated private struct EntryGeographyTarget: Sendable {
    let id: UUID
    let original: EntryGeographySnapshot
}

nonisolated private struct EntryGeographyUpdate: Sendable {
    let id: UUID
    let original: EntryGeographySnapshot
    let enriched: EntryGeographySnapshot
}

nonisolated private struct EntryGeographySnapshot: Equatable, Sendable {
    let transitOrigin: Location?
    let transitDestination: Location?
    let transitOriginCandidates: [LocationCandidate]
    let transitDestinationCandidates: [LocationCandidate]
    let visitLocation: Location?
    let visitCandidates: [LocationCandidate]
    let workoutSource: Location?
    let workoutOrigin: Location?
    let workoutDestination: Location?

    var needsEnrichment: Bool {
        let locations = [
            transitOrigin,
            transitDestination,
            visitLocation,
            workoutSource,
            workoutOrigin,
            workoutDestination,
        ] + transitOriginCandidates.map(\.location)
            + transitDestinationCandidates.map(\.location)
            + visitCandidates.map(\.location)
        return locations.contains { location in
            location.map {
                $0.cityName == nil
                    || $0.countryName == nil
                    || $0.countryCode == nil
            } ?? false
        }
    }
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
