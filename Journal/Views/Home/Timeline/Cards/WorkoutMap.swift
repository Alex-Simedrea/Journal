import MapKit
import Photos
import SwiftUI

struct TimelineWorkoutMiniMap: View {
    let occurrence: TimelineOccurrence
    @State private var routeModel = WorkoutRouteModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            TimelineWorkoutMapContent(
                occurrence: occurrence,
                points: routeModel.points
            )
            .environment(\.colorScheme, .dark)

            if let distance = occurrence.snapshot.workoutDistanceMeters {
                Text(
                    Measurement(value: distance, unit: UnitLength.meters),
                    format: .measurement(width: .abbreviated)
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.58), in: .capsule)
                .padding(6)
            }
        }
        .allowsHitTesting(false)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            if occurrence.snapshot.reviews.contains(where: {
                $0.target == .place || $0.target == .origin
                    || $0.target == .destination
            }) {
                TimelineReviewBadge().padding(5)
            }
        }
        .task(id: occurrence.snapshot.workoutUUID) {
            guard occurrence.snapshot.workoutMovementKind == .moving,
                let workoutUUID = occurrence.snapshot.workoutUUID
            else { return }
            await routeModel.load(workoutUUID: workoutUUID)
        }
    }
}

struct TimelineWorkoutMapContent: View {
    let occurrence: TimelineOccurrence
    let points: [WorkoutCoordinateSnapshot]
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        if occurrence.snapshot.workoutMovementKind == .moving {
            Map(position: $position) {
                if points.count > 1 {
                    MapPolyline(coordinates: points.map(\.coordinate))
                        .stroke(
                            .black.opacity(0.5),
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
                } else if let origin = workoutOrigin,
                    let destination = workoutDestination
                {
                    MapPolyline(
                        coordinates: [
                            origin.coordinate, destination.coordinate,
                        ]
                    )
                    .stroke(Color(hex: 0xB6FF00), lineWidth: 4)
                }

                if let origin = workoutOrigin {
                    PlaceMapFeature(
                        name: origin.name,
                        coordinate: origin.coordinate,
                        systemImage: origin.systemImage,
                        accuracyRadiusMeters: origin.accuracyRadiusMeters,
                        radiusCenterCoordinate: origin.radiusCenterCoordinate
                    )
                }
                if let destination = workoutDestination {
                    PlaceMapFeature(
                        name: destination.name,
                        coordinate: destination.coordinate,
                        systemImage: destination.systemImage,
                        accuracyRadiusMeters:
                            destination.accuracyRadiusMeters,
                        radiusCenterCoordinate:
                            destination.radiusCenterCoordinate
                    )
                }
            }
            .mapStyle(.standard)
            .onChange(of: points, initial: true) { _, points in
                position = routePosition(points: points)
            }
        } else if let location = workoutPlace {
            Map(
                initialPosition: .region(
                    MKCoordinateRegion(
                        center: location.radiusCenterCoordinate
                            ?? location.coordinate,
                        latitudinalMeters: PlaceMapCamera.visibleDiameter(
                            accuracyRadiusMeters:
                                location.accuracyRadiusMeters,
                            minimum: 320
                        ),
                        longitudinalMeters: PlaceMapCamera.visibleDiameter(
                            accuracyRadiusMeters:
                                location.accuracyRadiusMeters,
                            minimum: 320
                        )
                    )
                )
            ) {
                PlaceMapFeature(
                    name: location.name,
                    coordinate: location.coordinate,
                    systemImage: location.systemImage,
                    accuracyRadiusMeters: location.accuracyRadiusMeters,
                    radiusCenterCoordinate: location.radiusCenterCoordinate
                )
            }
            .mapStyle(.standard)
        } else {
            TimelineMapUnavailableTile()
        }
    }

    private var workoutOrigin: TimelineWorkoutMapEndpoint? {
        guard
            let coordinate = points.first?.coordinate
                ?? occurrence.snapshot.workoutRouteStart?.coordinate
        else {
            return nil
        }
        return TimelineWorkoutMapEndpoint(
            name: occurrence.snapshot.workoutOrigin,
            systemImage: occurrence.snapshot.workoutOriginLocation?.systemImage
                ?? .mappin,
            coordinate: coordinate,
            accuracyRadiusMeters: occurrence.snapshot.workoutOriginLocation?
                .accuracyRadiusMeters ?? 0,
            radiusCenterCoordinate: occurrence.snapshot.workoutOriginLocation?
                .radiusCenterCoordinate
        )
    }

    private var workoutDestination: TimelineWorkoutMapEndpoint? {
        guard
            let coordinate = points.last?.coordinate
                ?? occurrence.snapshot.workoutRouteEnd?.coordinate
        else {
            return nil
        }
        return TimelineWorkoutMapEndpoint(
            name: occurrence.snapshot.workoutDestination,
            systemImage:
                occurrence.snapshot.workoutDestinationLocation?.systemImage
                ?? .mappin,
            coordinate: coordinate,
            accuracyRadiusMeters: occurrence.snapshot
                .workoutDestinationLocation?.accuracyRadiusMeters ?? 0,
            radiusCenterCoordinate: occurrence.snapshot
                .workoutDestinationLocation?.radiusCenterCoordinate
        )
    }

    private var workoutPlace: TimelineWorkoutMapEndpoint? {
        guard
            let coordinate = occurrence.snapshot.workoutRouteStart?.coordinate
                ?? occurrence.snapshot.workoutPlaceLocation?.coordinate
        else {
            return nil
        }
        return TimelineWorkoutMapEndpoint(
            name: occurrence.snapshot.workoutPlace,
            systemImage: occurrence.snapshot.workoutPlaceLocation?.systemImage
                ?? .mappin,
            coordinate: coordinate,
            accuracyRadiusMeters: occurrence.snapshot.workoutPlaceLocation?
                .accuracyRadiusMeters ?? 0,
            radiusCenterCoordinate: occurrence.snapshot.workoutPlaceLocation?
                .radiusCenterCoordinate
        )
    }

    private func routePosition(
        points: [WorkoutCoordinateSnapshot]
    ) -> MapCameraPosition {
        var coordinates = points.map(\.coordinate)
        if coordinates.count < 2 {
            coordinates = [workoutOrigin, workoutDestination]
                .compactMap { $0?.coordinate }
        }
        guard let first = coordinates.first else { return .automatic }
        guard coordinates.count > 1 else {
            return .region(
                MKCoordinateRegion(
                    center: first,
                    latitudinalMeters: 320,
                    longitudinalMeters: 320
                )
            )
        }

        var mapPoints = coordinates.map(MKMapPoint.init)
        for endpoint in [workoutOrigin, workoutDestination].compactMap({ $0 })
        where endpoint.accuracyRadiusMeters > 0 {
            let center = MKMapPoint(
                endpoint.radiusCenterCoordinate ?? endpoint.coordinate
            )
            let radius = endpoint.accuracyRadiusMeters
                * MKMapPointsPerMeterAtLatitude(
                    endpoint.radiusCenterCoordinate?.latitude
                        ?? endpoint.coordinate.latitude
                )
            mapPoints.append(contentsOf: [
                MKMapPoint(x: center.x - radius, y: center.y),
                MKMapPoint(x: center.x + radius, y: center.y),
                MKMapPoint(x: center.x, y: center.y - radius),
                MKMapPoint(x: center.x, y: center.y + radius),
            ])
        }
        let minX = mapPoints.map(\.x).min() ?? 0
        let maxX = mapPoints.map(\.x).max() ?? minX
        let minY = mapPoints.map(\.y).min() ?? 0
        let maxY = mapPoints.map(\.y).max() ?? minY
        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(first.latitude)
        let horizontalPadding = max((maxX - minX) * 0.12, pointsPerMeter * 90)
        let verticalPadding = max((maxY - minY) * 0.12, pointsPerMeter * 90)
        let rect = MKMapRect(
            x: minX - horizontalPadding,
            y: minY - verticalPadding,
            width: maxX - minX + horizontalPadding * 2,
            height: maxY - minY + verticalPadding * 2
        )
        return .rect(rect)
    }
}

struct TimelineWorkoutMapEndpoint {
    let name: String
    let systemImage: PlaceSystemImage
    let coordinate: CLLocationCoordinate2D
    let accuracyRadiusMeters: Double
    let radiusCenterCoordinate: CLLocationCoordinate2D?
}

struct TimelineMapUnavailableTile: View {
    var body: some View {
        ZStack {
            Color(uiColor: .tertiarySystemGroupedBackground)
            TimelineFixedSymbol(systemName: "map", size: 24)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Location unavailable")
    }
}
