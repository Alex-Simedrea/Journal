//
//  TransitDistanceService.swift
//  Journal
//

import CoreLocation
import MapKit
import SwiftData

@MainActor
enum TransitDistanceService {
    static func populateMissing(in modelContext: ModelContext) async {
        guard let entries = try? modelContext.fetch(FetchDescriptor<LogEntry>()) else {
            return
        }
        for entry in entries where entry.kind == .transit {
            guard entry.transitDetails?.distanceMeters == nil else { continue }
            await populate(entry, in: modelContext)
        }
    }

    static func populate(
        _ entry: LogEntry,
        in modelContext: ModelContext
    ) async {
        guard let details = entry.transitDetails,
              let origin = details.originLocation
                ?? details.originPlace?.location
                ?? details.originCandidates.first?.location,
              let destination = details.destinationLocation
                ?? details.destinationPlace?.location
                ?? details.destinationCandidates.first?.location else {
            return
        }

        let geodesicDistance = CLLocation(
            latitude: origin.latitude,
            longitude: origin.longitude
        ).distance(
            from: CLLocation(
                latitude: destination.latitude,
                longitude: destination.longitude
            )
        )

        if let transportType = transportType(for: details.type),
           let metrics = try? await TransitMapKitService.routeMetrics(
               from: origin.coordinate,
               to: destination.coordinate,
               transportType: transportType,
               departureDate: entry.startTime
           ) {
            details.distanceMeters = metrics.distanceMeters
        } else {
            details.distanceMeters = geodesicDistance
        }
        try? modelContext.save()
    }

    static func refreshInBackground(
        _ entry: LogEntry,
        in modelContext: ModelContext
    ) {
        entry.transitDetails?.distanceMeters = nil
        Task { await populate(entry, in: modelContext) }
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
