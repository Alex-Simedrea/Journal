//
//  TimelineOverviewData.swift
//  Journal
//

import MapKit

struct TimelineMapMarker: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let systemImage: PlaceSystemImage

    init(location: TimelineLocationSnapshot) {
        id = location.id
        name = location.name
        latitude = location.latitude
        longitude = location.longitude
        systemImage = location.systemImage
    }

    init(
        id: String,
        name: String,
        coordinate: CLLocationCoordinate2D,
        systemImage: PlaceSystemImage
    ) {
        self.id = id
        self.name = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.systemImage = systemImage
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum TimelineMapPathKind: Hashable, Sendable {
    case transit(String)
    case workout
}

struct TimelineMapPath: Hashable, Identifiable, Sendable {
    let id: UUID
    let kind: TimelineMapPathKind
    let coordinates: [CLLocationCoordinate2D]

    static func == (lhs: TimelineMapPath, rhs: TimelineMapPath) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.coordinates.elementsEqual(rhs.coordinates) {
                $0.latitude == $1.latitude && $0.longitude == $1.longitude
            }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(kind)
        hasher.combine(coordinates.count)
        for coordinate in coordinates {
            hasher.combine(coordinate.latitude)
            hasher.combine(coordinate.longitude)
        }
    }
}

struct TimelineOverviewData: Equatable, Sendable {
    var markers: [TimelineMapMarker] = []
    var paths: [TimelineMapPath] = []

    var hasContent: Bool { !markers.isEmpty || !paths.isEmpty }

    static func make(
        occurrences: [TimelineOccurrence],
        workoutRoutes: [UUID: [WorkoutCoordinateSnapshot]] = [:]
    ) -> TimelineOverviewData {
        var markersByID: [String: TimelineMapMarker] = [:]
        var paths: [TimelineMapPath] = []

        for occurrence in occurrences {
            switch occurrence.kind {
            case .placeVisit:
                if let location = occurrence.snapshot.visitLocation,
                   location.hasCoordinate {
                    markersByID[location.id] = TimelineMapMarker(location: location)
                }
            case .transit:
                let origin = occurrence.snapshot.originLocation
                let destination = occurrence.snapshot.destinationLocation
                if let origin, origin.hasCoordinate {
                    markersByID[origin.id] = TimelineMapMarker(location: origin)
                }
                if let destination, destination.hasCoordinate {
                    markersByID[destination.id] = TimelineMapMarker(location: destination)
                }
                if let origin,
                   let destination,
                   origin.hasCoordinate,
                   destination.hasCoordinate {
                    paths.append(
                        TimelineMapPath(
                            id: occurrence.entryID,
                            kind: .transit(occurrence.transitType),
                            coordinates: curvedCoordinates(
                                from: origin.coordinate,
                                to: destination.coordinate,
                                bendPositive: occurrence.entryID.uuid.0 % 2 == 0
                            )
                        )
                    )
                }
            case .workout:
                appendWorkout(
                    occurrence,
                    route: workoutRoutes[occurrence.entryID] ?? [],
                    markersByID: &markersByID,
                    paths: &paths
                )
            case .wakeUp:
                break
            }
        }

        return TimelineOverviewData(
            markers: markersByID.values.sorted { $0.id < $1.id },
            paths: paths
        )
    }

    private static func appendWorkout(
        _ occurrence: TimelineOccurrence,
        route: [WorkoutCoordinateSnapshot],
        markersByID: inout [String: TimelineMapMarker],
        paths: inout [TimelineMapPath]
    ) {
        let snapshot = occurrence.snapshot
        if snapshot.workoutMovementKind == .moving {
            if route.count > 1 {
                paths.append(
                    TimelineMapPath(
                        id: occurrence.entryID,
                        kind: .workout,
                        coordinates: route.map(\.coordinate)
                    )
                )
            }

            let start = route.first ?? snapshot.workoutRouteStart
            let end = route.last ?? snapshot.workoutRouteEnd
            if let start {
                let marker = TimelineMapMarker(
                    id: "\(occurrence.entryID.uuidString)-workout-start",
                    name: snapshot.workoutOrigin,
                    coordinate: start.coordinate,
                    systemImage: snapshot.workoutOriginLocation?.systemImage
                        ?? .mappin
                )
                markersByID[marker.id] = marker
            }
            if let end {
                let marker = TimelineMapMarker(
                    id: "\(occurrence.entryID.uuidString)-workout-end",
                    name: snapshot.workoutDestination,
                    coordinate: end.coordinate,
                    systemImage: snapshot.workoutDestinationLocation?.systemImage
                        ?? .mappin
                )
                markersByID[marker.id] = marker
            }
        } else if let coordinate = snapshot.workoutRouteStart?.coordinate
            ?? snapshot.workoutPlaceLocation?.coordinate {
            let marker = TimelineMapMarker(
                id: "\(occurrence.entryID.uuidString)-workout-place",
                name: snapshot.workoutPlace,
                coordinate: coordinate,
                systemImage: snapshot.workoutPlaceLocation?.systemImage
                    ?? .mappin
            )
            markersByID[marker.id] = marker
        }
    }

    private static func curvedCoordinates(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        bendPositive: Bool
    ) -> [CLLocationCoordinate2D] {
        let start = MKMapPoint(origin)
        let end = MKMapPoint(destination)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 1)
        let direction = bendPositive ? 1.0 : -1.0
        let control = MKMapPoint(
            x: (start.x + end.x) / 2 - dy / length * length * 0.18 * direction,
            y: (start.y + end.y) / 2 + dx / length * length * 0.18 * direction
        )

        return (0...32).map { index in
            let t = Double(index) / 32
            let inverse = 1 - t
            return MKMapPoint(
                x: inverse * inverse * start.x
                    + 2 * inverse * t * control.x
                    + t * t * end.x,
                y: inverse * inverse * start.y
                    + 2 * inverse * t * control.y
                    + t * t * end.y
            ).coordinate
        }
    }
}
