//
//  WorkoutPlaceMatcher.swift
//  Journal
//

import CoreLocation
import Foundation

nonisolated struct WorkoutCoordinateSnapshot: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracyMeters: Double

    init(
        latitude: Double,
        longitude: Double,
        horizontalAccuracyMeters: Double
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyMeters = max(0, horizontalAccuracyMeters)
    }

    init(_ location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracyMeters: location.horizontalAccuracy
        )
    }

    init(location: Location) {
        self.init(
            latitude: location.latitude,
            longitude: location.longitude,
            horizontalAccuracyMeters: 0
        )
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum WorkoutPlaceMatchResult {
    case matched(Place)
    case ambiguous
    case unmatched
}

enum WorkoutPlaceMatcher {
    static let minimumRadiusMeters = 50.0
    static let requiredRunnerUpSeparationMeters = 25.0

    static func match(
        coordinate: WorkoutCoordinateSnapshot,
        places: [Place]
    ) -> WorkoutPlaceMatchResult {
        let workoutLocation = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        let candidates = places.compactMap { place -> Candidate? in
            let placeLocation = CLLocation(
                latitude: place.location.latitude,
                longitude: place.location.longitude
            )
            let distance = workoutLocation.distance(from: placeLocation)
            let eligibleRadius = max(
                minimumRadiusMeters,
                place.accuracyRadiusMeters,
                coordinate.horizontalAccuracyMeters
            )
            guard distance <= eligibleRadius else { return nil }
            return Candidate(place: place, distanceMeters: distance)
        }.sorted {
            if $0.distanceMeters != $1.distanceMeters {
                return $0.distanceMeters < $1.distanceMeters
            }
            return $0.place.id.uuidString < $1.place.id.uuidString
        }

        guard let nearest = candidates.first else { return .unmatched }
        guard candidates.count > 1 else { return .matched(nearest.place) }

        let runnerUp = candidates[1]
        guard runnerUp.distanceMeters - nearest.distanceMeters
            >= requiredRunnerUpSeparationMeters else {
            return .ambiguous
        }
        return .matched(nearest.place)
    }

    private struct Candidate {
        let place: Place
        let distanceMeters: Double
    }
}
