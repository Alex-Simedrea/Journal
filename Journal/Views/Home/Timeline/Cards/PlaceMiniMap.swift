import MapKit
import Photos
import SwiftUI

struct TimelinePlaceMiniMap: View {
    let location: TimelineLocationSnapshot?
    let needsReview: Bool
    let cameraNorthOffsetFraction: Double

    init(
        location: TimelineLocationSnapshot?,
        needsReview: Bool,
        cameraNorthOffsetFraction: Double = 0
    ) {
        self.location = location
        self.needsReview = needsReview
        self.cameraNorthOffsetFraction = max(
            cameraNorthOffsetFraction,
            0
        )
    }

    var body: some View {
        ZStack {
            if let location, location.hasCoordinate {
                let visibleDiameter = PlaceMapCamera.visibleDiameter(
                    accuracyRadiusMeters: location.accuracyRadiusMeters,
                    minimum: 320
                )
                let featureCoordinate = location.radiusCenterCoordinate
                    ?? location.coordinate
                Map(
                    initialPosition: .region(
                        MKCoordinateRegion(
                            center: PlaceMapCamera.center(
                                northOf: featureCoordinate,
                                byMeters: visibleDiameter
                                    * cameraNorthOffsetFraction
                            ),
                            latitudinalMeters: visibleDiameter,
                            longitudinalMeters: visibleDiameter
                        )
                    )
                ) {
                    PlaceMapFeature(location: location)
                }
                .mapStyle(.standard)
            } else {
                TimelineMapUnavailableTile()
            }
        }
        .allowsHitTesting(false)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            if needsReview {
                ReviewBadge(size: 17).padding(5)
            }
        }
    }
}
