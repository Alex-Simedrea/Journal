//
//  TimelineOverviewData.swift
//  Journal
//

import MapKit

nonisolated struct TimelineMapMarker: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let systemImage: PlaceSystemImage
    let accuracyRadiusMeters: Double
    let radiusCenterLatitude: Double?
    let radiusCenterLongitude: Double?

    init(location: TimelineLocationSnapshot) {
        id = location.id
        name = location.name
        latitude = location.latitude
        longitude = location.longitude
        systemImage = location.systemImage
        accuracyRadiusMeters = location.accuracyRadiusMeters
        radiusCenterLatitude = location.radiusCenterLatitude
        radiusCenterLongitude = location.radiusCenterLongitude
    }

    init(
        id: String,
        name: String,
        coordinate: CLLocationCoordinate2D,
        systemImage: PlaceSystemImage,
        accuracyRadiusMeters: Double = 0,
        radiusCenterCoordinate: CLLocationCoordinate2D? = nil
    ) {
        self.id = id
        self.name = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.systemImage = systemImage
        self.accuracyRadiusMeters = max(accuracyRadiusMeters, 0)
        radiusCenterLatitude = radiusCenterCoordinate?.latitude
        radiusCenterLongitude = radiusCenterCoordinate?.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var radiusCenterCoordinate: CLLocationCoordinate2D? {
        guard let radiusCenterLatitude, let radiusCenterLongitude else {
            return nil
        }
        return CLLocationCoordinate2D(
            latitude: radiusCenterLatitude,
            longitude: radiusCenterLongitude
        )
    }

    var displayCoordinate: CLLocationCoordinate2D {
        accuracyRadiusMeters > 0
            ? radiusCenterCoordinate ?? coordinate
            : coordinate
    }
}

nonisolated enum TimelineMapPathKind: Hashable, Sendable {
    case transit(String)
    case workout
}

nonisolated enum TimelineMapPathDisplayMode: Equatable, Sendable {
    case all
    case visibleAtMapScale
}

nonisolated struct TimelineMapPath: Hashable, Identifiable, Sendable {
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

nonisolated struct TimelineOverviewData: Equatable, Sendable {
    var markers: [TimelineMapMarker]
    var paths: [TimelineMapPath]
    var pathDisplayMode: TimelineMapPathDisplayMode

    init(
        markers: [TimelineMapMarker] = [],
        paths: [TimelineMapPath] = [],
        pathDisplayMode: TimelineMapPathDisplayMode = .all
    ) {
        self.markers = Self.deduplicated(markers)
        self.paths = paths
        self.pathDisplayMode = pathDisplayMode
    }

    var hasContent: Bool { !markers.isEmpty || !paths.isEmpty }

    static func make(
        occurrences: [TimelineOccurrence],
        workoutRoutes: [UUID: [WorkoutCoordinateSnapshot]] = [:]
    ) -> TimelineOverviewData {
        TimelineOverviewData(
            markers: markers(
                for: occurrences,
                workoutRoutes: workoutRoutes
            ),
            paths: paths(
                for: occurrences,
                workoutRoutes: workoutRoutes
            )
        )
    }

    static func makePeriod(
        occurrences: [TimelineOccurrence]
    ) -> TimelineOverviewData {
        let candidates = markerCandidates(for: occurrences)
        let cityKeys = Set(candidates.compactMap(\.cityKey))
        let selectedMarkers = cityKeys.count > 1
            ? cityMarkers(from: candidates)
            : markers(from: candidates)
        return TimelineOverviewData(
            markers: selectedMarkers,
            paths: paths(for: occurrences, workoutRoutes: [:]),
            pathDisplayMode: .visibleAtMapScale
        )
    }

    private struct MarkerCandidate {
        let marker: TimelineMapMarker
        let cityName: String?
        let countryName: String?
        let countryCode: String?

        init(
            marker: TimelineMapMarker,
            location: TimelineLocationSnapshot?
        ) {
            self.marker = marker
            cityName = location?.cityName
            countryName = location?.countryName
            countryCode = location?.countryCode
        }

        var cityKey: String? {
            guard let cityName else { return nil }
            let city = normalized(cityName)
            guard !city.isEmpty else { return nil }
            let country = normalized(countryCode ?? countryName ?? "")
            return "\(city)|\(country)"
        }

        private func normalized(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines).folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            ).lowercased(with: Locale(identifier: "en_US_POSIX"))
        }
    }

    private static func markers(
        for occurrences: [TimelineOccurrence],
        workoutRoutes: [UUID: [WorkoutCoordinateSnapshot]]
    ) -> [TimelineMapMarker] {
        markers(from: markerCandidates(
            for: occurrences,
            workoutRoutes: workoutRoutes
        ))
    }

    private static func markers(
        from candidates: [MarkerCandidate]
    ) -> [TimelineMapMarker] {
        var markersByID: [String: TimelineMapMarker] = [:]
        for candidate in candidates {
            markersByID[candidate.marker.id] = candidate.marker
        }
        return markersByID.values.sorted { $0.id < $1.id }
    }

    private static func markerCandidates(
        for occurrences: [TimelineOccurrence],
        workoutRoutes: [UUID: [WorkoutCoordinateSnapshot]] = [:]
    ) -> [MarkerCandidate] {
        var candidates: [MarkerCandidate] = []

        for occurrence in occurrences {
            switch occurrence.kind {
            case .placeVisit:
                if let location = occurrence.snapshot.visitLocation,
                   location.hasCoordinate {
                    candidates.append(MarkerCandidate(
                        marker: TimelineMapMarker(location: location),
                        location: location
                    ))
                }
            case .transit:
                let origin = occurrence.snapshot.originLocation
                let destination = occurrence.snapshot.destinationLocation
                if let origin, origin.hasCoordinate {
                    candidates.append(MarkerCandidate(
                        marker: TimelineMapMarker(location: origin),
                        location: origin
                    ))
                }
                if let destination, destination.hasCoordinate {
                    candidates.append(MarkerCandidate(
                        marker: TimelineMapMarker(location: destination),
                        location: destination
                    ))
                }
            case .workout:
                appendWorkoutMarkers(
                    occurrence,
                    route: workoutRoutes[occurrence.entryID] ?? [],
                    to: &candidates
                )
            case .wakeUp:
                break
            }
        }
        return candidates
    }

    private static func appendWorkoutMarkers(
        _ occurrence: TimelineOccurrence,
        route: [WorkoutCoordinateSnapshot],
        to candidates: inout [MarkerCandidate]
    ) {
        let snapshot = occurrence.snapshot
        if snapshot.workoutMovementKind == .moving {
            let start = route.first ?? snapshot.workoutRouteStart
            let end = route.last ?? snapshot.workoutRouteEnd
            if let start {
                let marker = TimelineMapMarker(
                    id: "\(occurrence.entryID.uuidString)-workout-start",
                    name: snapshot.workoutOrigin,
                    coordinate: start.coordinate,
                    systemImage: snapshot.workoutOriginLocation?.systemImage
                        ?? .mappin,
                    accuracyRadiusMeters: snapshot.workoutOriginLocation?
                        .accuracyRadiusMeters ?? 0,
                    radiusCenterCoordinate: snapshot.workoutOriginLocation?
                        .radiusCenterCoordinate
                )
                candidates.append(MarkerCandidate(
                    marker: marker,
                    location: snapshot.workoutOriginLocation
                ))
            }
            if let end {
                let marker = TimelineMapMarker(
                    id: "\(occurrence.entryID.uuidString)-workout-end",
                    name: snapshot.workoutDestination,
                    coordinate: end.coordinate,
                    systemImage: snapshot.workoutDestinationLocation?.systemImage
                        ?? .mappin,
                    accuracyRadiusMeters: snapshot.workoutDestinationLocation?
                        .accuracyRadiusMeters ?? 0,
                    radiusCenterCoordinate: snapshot.workoutDestinationLocation?
                        .radiusCenterCoordinate
                )
                candidates.append(MarkerCandidate(
                    marker: marker,
                    location: snapshot.workoutDestinationLocation
                ))
            }
        } else if let coordinate = snapshot.workoutRouteStart?.coordinate
            ?? snapshot.workoutPlaceLocation?.coordinate {
            let marker = TimelineMapMarker(
                id: "\(occurrence.entryID.uuidString)-workout-place",
                name: snapshot.workoutPlace,
                coordinate: coordinate,
                systemImage: snapshot.workoutPlaceLocation?.systemImage
                    ?? .mappin,
                accuracyRadiusMeters: snapshot.workoutPlaceLocation?
                    .accuracyRadiusMeters ?? 0,
                radiusCenterCoordinate: snapshot.workoutPlaceLocation?
                    .radiusCenterCoordinate
            )
            candidates.append(MarkerCandidate(
                marker: marker,
                location: snapshot.workoutPlaceLocation
            ))
        }
    }

    private static func paths(
        for occurrences: [TimelineOccurrence],
        workoutRoutes: [UUID: [WorkoutCoordinateSnapshot]]
    ) -> [TimelineMapPath] {
        var paths: [TimelineMapPath] = []
        for occurrence in occurrences {
            switch occurrence.kind {
            case .transit:
                let origin = occurrence.snapshot.originLocation
                let destination = occurrence.snapshot.destinationLocation
                let route = TransitRouteGeometry.coordinates(
                    recordedRoute: occurrence.snapshot.transitRecordedRoute,
                    origin: origin?.hasCoordinate == true
                        ? origin?.coordinate
                        : nil,
                    destination: destination?.hasCoordinate == true
                        ? destination?.coordinate
                        : nil,
                    bendPositive: occurrence.entryID.uuid.0 % 2 == 0
                )
                if route.count > 1 {
                    paths.append(TimelineMapPath(
                        id: occurrence.entryID,
                        kind: .transit(occurrence.transitType),
                        coordinates: route
                    ))
                }
            case .workout:
                let route = workoutRoutes[occurrence.entryID] ?? []
                if occurrence.snapshot.workoutMovementKind == .moving,
                   route.count > 1 {
                    paths.append(TimelineMapPath(
                        id: occurrence.entryID,
                        kind: .workout,
                        coordinates: route.map(\.coordinate)
                    ))
                }
            case .placeVisit, .wakeUp:
                break
            }
        }
        return paths
    }

    private static func cityMarkers(
        from candidates: [MarkerCandidate]
    ) -> [TimelineMapMarker] {
        let grouped = Dictionary(grouping: candidates) {
            $0.cityKey
        }
        return grouped.compactMap { key, values in
            guard let key,
                  let cityName = values.compactMap(\.cityName).first,
                  let representative = cityRepresentative(in: values) else {
                return nil
            }
            return TimelineMapMarker(
                id: "city-\(key)",
                name: cityName.trimmingCharacters(in: .whitespacesAndNewlines),
                coordinate: representative.marker.displayCoordinate,
                systemImage: .buildings
            )
        }.sorted { $0.id < $1.id }
    }

    private static func cityRepresentative(
        in candidates: [MarkerCandidate]
    ) -> MarkerCandidate? {
        guard !candidates.isEmpty else { return nil }
        let latitude = candidates.reduce(0) {
            $0 + $1.marker.displayCoordinate.latitude
        } / Double(candidates.count)
        let longitude = candidates.reduce(0) {
            $0 + $1.marker.displayCoordinate.longitude
        } / Double(candidates.count)
        func distanceSquared(_ coordinate: CLLocationCoordinate2D) -> Double {
            let latitudeDelta = coordinate.latitude - latitude
            let longitudeDelta = (coordinate.longitude - longitude)
                * cos(latitude * .pi / 180)
            return latitudeDelta * latitudeDelta
                + longitudeDelta * longitudeDelta
        }
        return candidates.min { lhs, rhs in
            distanceSquared(lhs.marker.displayCoordinate)
                < distanceSquared(rhs.marker.displayCoordinate)
        }
    }

    private struct MarkerCoordinateKey: Hashable {
        let latitude: Int
        let longitude: Int
    }

    private static func deduplicated(
        _ markers: [TimelineMapMarker]
    ) -> [TimelineMapMarker] {
        var coordinates = Set<MarkerCoordinateKey>()
        return markers.filter { marker in
            let coordinate = marker.displayCoordinate
            let key = MarkerCoordinateKey(
                latitude: Int((coordinate.latitude * 100_000).rounded()),
                longitude: Int((coordinate.longitude * 100_000).rounded())
            )
            return coordinates.insert(key).inserted
        }
    }

    static func curvedCoordinates(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        bendPositive: Bool
    ) -> [CLLocationCoordinate2D] {
        TransitRouteGeometry.curvedCoordinates(
            from: origin,
            to: destination,
            bendPositive: bendPositive
        )
    }
}
