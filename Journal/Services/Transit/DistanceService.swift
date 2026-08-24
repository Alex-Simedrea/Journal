//
//  TransitDistanceService.swift
//  Journal
//

import CoreLocation
import MapKit
import SwiftData

private struct TransitDistanceRequest: Equatable {
    let origin: Location
    let destination: Location
    let transitType: String
    let departureDate: Date?
}

@MainActor
enum TransitDistanceService {
    static func populateMissing(in modelContext: ModelContext) async {
        guard let entryIDs = try? modelContext.fetch(
            FetchDescriptor<LogEntry>()
        ).compactMap({ entry in
            entry.kind == .transit
                && entry.transitDetails?.distanceMeters == nil
                ? entry.id
                : nil
        }) else {
            return
        }
        for entryID in entryIDs {
            await populate(entryID: entryID, in: modelContext)
        }
    }

    static func populate(
        _ entry: LogEntry,
        in modelContext: ModelContext
    ) async {
        await populate(entryID: entry.id, in: modelContext)
    }

    static func populate(
        entryID: UUID,
        in modelContext: ModelContext
    ) async {
        guard let routeRequest = try? request(
            forEntryID: entryID,
            in: modelContext
        ) else {
            return
        }

        let geodesicDistance = CLLocation(
            latitude: routeRequest.origin.latitude,
            longitude: routeRequest.origin.longitude
        ).distance(
            from: CLLocation(
                latitude: routeRequest.destination.latitude,
                longitude: routeRequest.destination.longitude
            )
        )

        let distance: Double
        if let transportType = transportType(for: routeRequest.transitType),
           let metrics = try? await TransitMapKitService.routeMetrics(
               from: routeRequest.origin.coordinate,
               to: routeRequest.destination.coordinate,
               transportType: transportType,
               departureDate: routeRequest.departureDate
           ) {
            distance = metrics.distanceMeters
        } else {
            distance = geodesicDistance
        }

        guard let currentRequest = try? request(
            forEntryID: entryID,
            in: modelContext
        ), currentRequest == routeRequest,
              let entry = try? entry(withID: entryID, in: modelContext),
              let details = entry.transitDetails else { return }
        details.distanceMeters = distance
        try? modelContext.save()
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
            let enrichmentContext = ModelContext(container)
            enrichmentContext.autosaveEnabled = false
            await populate(entryID: entryID, in: enrichmentContext)
        }
    }

    private static func request(
        forEntryID entryID: UUID,
        in modelContext: ModelContext
    ) throws -> TransitDistanceRequest? {
        guard let entry = try entry(withID: entryID, in: modelContext),
              let details = entry.transitDetails,
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
