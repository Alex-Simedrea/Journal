//
//  TransitDistanceService.swift
//  Journal
//

import CoreLocation
import MapKit
import SwiftData

nonisolated private struct TransitDistanceRequest: Equatable, Sendable {
    let origin: Location
    let destination: Location
    let transitType: String
    let departureDate: Date?
}

nonisolated private struct TransitDistanceUpdate: Sendable {
    let entryID: UUID
    let request: TransitDistanceRequest
    let distanceMeters: Double
}

nonisolated enum TransitDistanceService {
    static func populateMissing(in modelContext: ModelContext) async {
        guard let requests = try? modelContext.fetch(
            FetchDescriptor<LogEntry>()
        ).compactMap({ entry -> (UUID, TransitDistanceRequest)? in
            guard entry.kind == .transit,
                  entry.transitDetails?.distanceMeters == nil,
                  let request = request(for: entry) else { return nil }
            return (entry.id, request)
        }), !requests.isEmpty else {
            return
        }

        var updates: [TransitDistanceUpdate] = []
        updates.reserveCapacity(requests.count)
        for (entryID, request) in requests {
            updates.append(TransitDistanceUpdate(
                entryID: entryID,
                request: request,
                distanceMeters: await distance(for: request)
            ))
        }

        guard let currentEntries = try? modelContext.fetch(
            FetchDescriptor<LogEntry>()
        ) else { return }
        let entriesByID = Dictionary(
            uniqueKeysWithValues: currentEntries.map { ($0.id, $0) }
        )
        var changed = false
        for update in updates {
            guard let entry = entriesByID[update.entryID],
                  request(for: entry) == update.request,
                  let details = entry.transitDetails,
                  details.distanceMeters == nil else { continue }
            details.distanceMeters = update.distanceMeters
            changed = true
        }
        guard changed else { return }
        do {
            try modelContext.save()
            await TimelineDataChange.post()
        } catch {
            modelContext.rollback()
        }
    }

    static func populate(
        _ entry: LogEntry,
        in modelContext: ModelContext,
        postsTimelineChange: Bool = true
    ) async {
        await populate(
            entryID: entry.id,
            in: modelContext,
            postsTimelineChange: postsTimelineChange
        )
    }

    static func populate(
        entryID: UUID,
        in modelContext: ModelContext,
        postsTimelineChange: Bool = true
    ) async {
        guard let routeRequest = try? request(
            forEntryID: entryID,
            in: modelContext
        ) else {
            return
        }

        let resolvedDistance = await distance(for: routeRequest)

        guard let currentRequest = try? request(
            forEntryID: entryID,
            in: modelContext
        ), currentRequest == routeRequest,
              let entry = try? entry(withID: entryID, in: modelContext),
              let details = entry.transitDetails else { return }
        details.distanceMeters = resolvedDistance
        do {
            try modelContext.save()
            if postsTimelineChange {
                await TimelineDataChange.post()
            }
        } catch {
            modelContext.rollback()
        }
    }

    static func refreshInBackground(
        _ entry: LogEntry,
        in modelContext: ModelContext
    ) {
        let entryID = entry.id
        let container = modelContext.container
        entry.transitDetails?.distanceMeters = nil
        try? modelContext.save()
        Task {
            let maintenance = await JournalPersistenceActors.shared.maintenance(
                for: JournalModelContainerReference(container)
            )
            await maintenance.populateTransitDistance(entryID: entryID)
        }
    }

    private static func request(
        forEntryID entryID: UUID,
        in modelContext: ModelContext
    ) throws -> TransitDistanceRequest? {
        guard let entry = try entry(withID: entryID, in: modelContext) else {
            return nil
        }
        return request(for: entry)
    }

    private static func request(
        for entry: LogEntry
    ) -> TransitDistanceRequest? {
        guard let details = entry.transitDetails,
              let origin = details.originLocation
                ?? details.originPlace?.location
                ?? details.originCandidates.first?.location,
              let destination = details.destinationLocation
                ?? details.destinationPlace?.location
                ?? details.destinationCandidates.first?.location else {
            return nil
        }
        return TransitDistanceRequest(
            origin: origin,
            destination: destination,
            transitType: details.type,
            departureDate: entry.startTime
        )
    }

    private static func distance(
        for request: TransitDistanceRequest
    ) async -> Double {
        await Task.detached(priority: .utility) {
            await resolvedDistance(for: request)
        }.value
    }

    private static func resolvedDistance(
        for request: TransitDistanceRequest
    ) async -> Double {
        let geodesicDistance = CLLocation(
            latitude: request.origin.latitude,
            longitude: request.origin.longitude
        ).distance(
            from: CLLocation(
                latitude: request.destination.latitude,
                longitude: request.destination.longitude
            )
        )
        guard let transportType = transportType(for: request.transitType),
              let metrics = try? await TransitMapKitService.routeMetrics(
                  from: request.origin.coordinate,
                  to: request.destination.coordinate,
                  transportType: transportType,
                  departureDate: request.departureDate
              ) else {
            return geodesicDistance
        }
        return metrics.distanceMeters
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

    private static func transportType(
        for transitType: String
    ) -> MKDirectionsTransportType? {
        switch transitType.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ) {
        case "walk": .walking
        case "motorcycle", "car", "taxi", "ride share", "uber", "bolt", "lyft":
            .automobile
        case "bus", "train", "metro", "tram", "ferry":
            .transit
        default:
            nil
        }
    }
}
