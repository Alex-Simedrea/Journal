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
            let places = try modelContext.fetch(FetchDescriptor<Place>())
            let entries = try modelContext.fetch(FetchDescriptor<LogEntry>())
            var changed = false

            for place in places where needsEnrichment(place.location) {
                let enriched = await LocationGeographyClient.shared.enriched(
                    place.location
                )
                if enriched != place.location {
                    place.location = enriched
                    changed = true
                }
            }

            for entry in entries {
                if let details = entry.transitDetails {
                    changed = await enrich(&details.originLocation) || changed
                    changed = await enrich(&details.destinationLocation) || changed
                    let origins = await enrich(details.originCandidates)
                    let destinations = await enrich(details.destinationCandidates)
                    if origins != details.originCandidates {
                        details.originCandidates = origins
                        changed = true
                    }
                    if destinations != details.destinationCandidates {
                        details.destinationCandidates = destinations
                        changed = true
                    }
                }
                if let details = entry.placeVisitDetails {
                    changed = await enrich(&details.location) || changed
                    let candidates = await enrich(details.candidates)
                    if candidates != details.candidates {
                        details.candidates = candidates
                        changed = true
                    }
                }
                if let details = entry.workoutDetails {
                    changed = await enrich(&details.sourceLocation) || changed
                    changed = await enrich(&details.originLocation) || changed
                    changed = await enrich(&details.destinationLocation) || changed
                }
            }

            if changed { try modelContext.save() }
        } catch {
            // Geography is supplementary; partial summaries remain useful.
        }
    }

    private static func enrich(_ location: inout Location?) async -> Bool {
        guard let current = location, needsEnrichment(current) else {
            return false
        }
        let enriched = await LocationGeographyClient.shared.enriched(current)
        guard enriched != current else { return false }
        location = enriched
        return true
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
