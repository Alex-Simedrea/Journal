//
//  EntryDetailCards.swift
//  Journal
//

import MapKit
import Photos
import SwiftUI

struct EntryDetailMapCard: View {
    let entry: LogEntry
    let routeModel: WorkoutRouteModel
    let needsReview: Bool
    let onEdit: () -> Void

    var body: some View {
        EntryDetailMapContent(entry: entry, points: routeModel.points)
            .aspectRatio(
                entry.kind == .placeVisit ? 2.35 : 1.57,
                contentMode: .fit
            )
            .clipShape(.rect(cornerRadius: 22))
            .overlay(alignment: .topTrailing) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.title3.weight(.medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .padding(.top, 12)
                .padding(.trailing, 12)
                .accessibilityLabel("Edit locations")
            }
            .overlay(alignment: .bottomTrailing) {
                if needsReview {
                    EntryDetailReviewBadge()
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                }
            }
            .task(id: workoutUUID) {
                guard let workoutUUID else { return }
                await routeModel.load(workoutUUID: workoutUUID)
            }
    }

    private var workoutUUID: UUID? {
        guard entry.kind == .workout,
            entry.workoutDetails?.movementKind == .moving
        else {
            return nil
        }
        return entry.workoutDetails?.healthKitWorkoutUUID
    }
}

private struct EntryDetailMapContent: View {
    let entry: LogEntry
    let points: [WorkoutCoordinateSnapshot]

    var body: some View {
        Map(initialPosition: initialPosition, interactionModes: []) {
            switch entry.kind {
            case .placeVisit:
                if let endpoint = visitEndpoint {
                    EntryDetailMapMarker(endpoint: endpoint)
                }
            case .transit:
                if let origin = transitOrigin,
                    let destination = transitDestination
                {
                    MapPolyline(
                        coordinates: TimelineOverviewData.curvedCoordinates(
                            from: origin.location.coordinate,
                            to: destination.location.coordinate,
                            bendPositive: true
                        )
                    )
                    .stroke(
                        TransitPresentationCatalog.presentation(
                            for: entry.transitDetails?.type ?? "Transit"
                        ).color.opacity(0.82),
                        style: StrokeStyle(
                            lineWidth: 4,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
                if let transitOrigin {
                    EntryDetailMapMarker(endpoint: transitOrigin)
                }
                if let transitDestination {
                    EntryDetailMapMarker(endpoint: transitDestination)
                }
            case .workout:
                if points.count > 1 {
                    MapPolyline(coordinates: points.map(\.coordinate))
                        .stroke(
                            .black.opacity(0.48),
                            style: StrokeStyle(
                                lineWidth: 7,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    MapPolyline(coordinates: points.map(\.coordinate))
                        .stroke(
                            Color(hex: 0xB6FF00),
                            style: StrokeStyle(
                                lineWidth: 4,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }
                if let workoutOrigin {
                    EntryDetailMapMarker(endpoint: workoutOrigin)
                }
                if let workoutDestination {
                    EntryDetailMapMarker(endpoint: workoutDestination)
                }
                if points.isEmpty, let workoutPlace {
                    EntryDetailMapMarker(endpoint: workoutPlace)
                }
            case .wakeUp:
                EmptyMapContent()
            }
        }
        .mapStyle(.standard)
        .allowsHitTesting(false)
    }

    private var initialPosition: MapCameraPosition {
        guard entry.kind == .placeVisit, let visitEndpoint else {
            return .automatic
        }
        return .region(
            MKCoordinateRegion(
                center: visitEndpoint.radiusCenterCoordinate
                    ?? visitEndpoint.location.coordinate,
                latitudinalMeters: PlaceMapCamera.visibleDiameter(
                    accuracyRadiusMeters: visitEndpoint.accuracyRadiusMeters,
                    minimum: 700
                ),
                longitudinalMeters: PlaceMapCamera.visibleDiameter(
                    accuracyRadiusMeters: visitEndpoint.accuracyRadiusMeters,
                    minimum: 700
                )
            )
        )
    }

    private var visitEndpoint: EntryDetailMapEndpoint? {
        guard let details = entry.placeVisitDetails,
            let location = details.location ?? details.place?.location
        else {
            return nil
        }
        return EntryDetailMapEndpoint(
            name: details.place?.name ?? location.preferredName ?? "Place",
            location: location,
            systemImage: details.place?.systemImage ?? .mappin,
            accuracyRadiusMeters: details.place?.accuracyRadiusMeters ?? 0,
            radiusCenterCoordinate: details.place?.location.coordinate
        )
    }

    private var transitOrigin: EntryDetailMapEndpoint? {
        guard let details = entry.transitDetails,
            let location = details.originLocation
                ?? details.originPlace?.location
        else { return nil }
        return EntryDetailMapEndpoint(
            name: details.originPlace?.name
                ?? location.preferredName
                ?? "Origin",
            location: location,
            systemImage: details.originPlace?.systemImage ?? .mappin,
            accuracyRadiusMeters:
                details.originPlace?.accuracyRadiusMeters ?? 0,
            radiusCenterCoordinate: details.originPlace?.location.coordinate
        )
    }

    private var transitDestination: EntryDetailMapEndpoint? {
        guard let details = entry.transitDetails,
            let location = details.destinationLocation
                ?? details.destinationPlace?.location
        else { return nil }
        return EntryDetailMapEndpoint(
            name: details.destinationPlace?.name
                ?? location.preferredName
                ?? "Destination",
            location: location,
            systemImage: details.destinationPlace?.systemImage ?? .mappin,
            accuracyRadiusMeters:
                details.destinationPlace?.accuracyRadiusMeters ?? 0,
            radiusCenterCoordinate:
                details.destinationPlace?.location.coordinate
        )
    }

    private var workoutOrigin: EntryDetailMapEndpoint? {
        guard entry.workoutDetails?.movementKind == .moving,
            let location = points.first.map({ point in
                Location(
                    latitude: point.latitude,
                    longitude: point.longitude
                )
            }) ?? entry.workoutDetails?.originLocation
        else { return nil }
        return EntryDetailMapEndpoint(
            name: entry.workoutDetails?.originPlace?.name ?? "Origin",
            location: location,
            systemImage: entry.workoutDetails?.originPlace?.systemImage
                ?? .mappin,
            accuracyRadiusMeters:
                entry.workoutDetails?.originPlace?.accuracyRadiusMeters ?? 0,
            radiusCenterCoordinate:
                entry.workoutDetails?.originPlace?.location.coordinate
        )
    }

    private var workoutDestination: EntryDetailMapEndpoint? {
        guard entry.workoutDetails?.movementKind == .moving,
            let location = points.last.map({ point in
                Location(
                    latitude: point.latitude,
                    longitude: point.longitude
                )
            }) ?? entry.workoutDetails?.destinationLocation
        else {
            return nil
        }
        return EntryDetailMapEndpoint(
            name: entry.workoutDetails?.destinationPlace?.name
                ?? "Destination",
            location: location,
            systemImage: entry.workoutDetails?.destinationPlace?.systemImage
                ?? .mappin,
            accuracyRadiusMeters:
                entry.workoutDetails?.destinationPlace?.accuracyRadiusMeters
                ?? 0,
            radiusCenterCoordinate:
                entry.workoutDetails?.destinationPlace?.location.coordinate
        )
    }

    private var workoutPlace: EntryDetailMapEndpoint? {
        guard entry.workoutDetails?.movementKind != .moving,
            let location = entry.workoutDetails?.sourceLocation
                ?? entry.workoutDetails?.place?.location
        else { return nil }
        return EntryDetailMapEndpoint(
            name: entry.workoutDetails?.place?.name ?? "Workout location",
            location: location,
            systemImage: entry.workoutDetails?.place?.systemImage ?? .mappin,
            accuracyRadiusMeters:
                entry.workoutDetails?.place?.accuracyRadiusMeters ?? 0,
            radiusCenterCoordinate:
                entry.workoutDetails?.place?.location.coordinate
        )
    }
}

private struct EmptyMapContent: MapContent {
    var body: some MapContent {
        MapCircle(center: .init(), radius: 0).foregroundStyle(.clear)
    }
}

private struct EntryDetailMapEndpoint {
    let name: String
    let location: Location
    let systemImage: PlaceSystemImage
    let accuracyRadiusMeters: Double
    let radiusCenterCoordinate: CLLocationCoordinate2D?
}

private struct EntryDetailMapMarker: MapContent {
    let endpoint: EntryDetailMapEndpoint

    var body: some MapContent {
        PlaceMapFeature(
            name: endpoint.name,
            coordinate: endpoint.location.coordinate,
            systemImage: endpoint.systemImage,
            accuracyRadiusMeters: endpoint.accuracyRadiusMeters,
            radiusCenterCoordinate: endpoint.radiusCenterCoordinate
        )
    }
}
