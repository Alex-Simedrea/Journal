import CoreLocation
import MapKit
import SwiftUI

enum JournalMapDisplayStylePolicy {
    nonisolated static let hybridDistanceThresholdMeters: CLLocationDistance =
        3_000_000

    nonisolated static func usesHybridStyle(
        for coordinates: [CLLocationCoordinate2D]
    ) -> Bool {
        let vectors = representativeCoordinates(from: coordinates).map(
            UnitVector.init
        )
        guard vectors.count > 1 else { return false }
        let thresholdAngle = hybridDistanceThresholdMeters / earthRadiusMeters
        let thresholdChord = 2 * sin(thresholdAngle / 2)
        let thresholdSquared = thresholdChord * thresholdChord
        for firstIndex in vectors.indices.dropLast() {
            for secondIndex in vectors.index(after: firstIndex)..<vectors.endIndex {
                if vectors[firstIndex].squaredDistance(
                    to: vectors[secondIndex]
                ) > thresholdSquared {
                    return true
                }
            }
        }
        return false
    }

    static func mapStyle(
        for coordinates: [CLLocationCoordinate2D]
    ) -> MapStyle {
        usesHybridStyle(for: coordinates)
            ? .hybrid(elevation: .realistic)
            : .standard
    }

    nonisolated private static let earthRadiusMeters = 6_371_008.8
    nonisolated private static let maximumPolicyCoordinateCount = 96

    nonisolated private static func representativeCoordinates(
        from coordinates: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D] {
        let valid = coordinates.filter {
            $0.latitude.isFinite && $0.longitude.isFinite
                && (-90...90).contains($0.latitude)
                && (-180...180).contains($0.longitude)
        }
        guard valid.count > maximumPolicyCoordinateCount else { return valid }
        let lastIndex = valid.count - 1
        return (0..<maximumPolicyCoordinateCount).map { index in
            valid[index * lastIndex / (maximumPolicyCoordinateCount - 1)]
        }
    }

    nonisolated private struct UnitVector {
        let x: Double
        let y: Double
        let z: Double

        init(_ coordinate: CLLocationCoordinate2D) {
            let latitude = coordinate.latitude * .pi / 180
            let longitude = coordinate.longitude * .pi / 180
            let latitudeCosine = cos(latitude)
            x = latitudeCosine * cos(longitude)
            y = latitudeCosine * sin(longitude)
            z = sin(latitude)
        }

        func squaredDistance(to other: UnitVector) -> Double {
            let xDelta = x - other.x
            let yDelta = y - other.y
            let zDelta = z - other.z
            return xDelta * xDelta + yDelta * yDelta + zDelta * zDelta
        }
    }
}
