import MapKit
import Photos
import SwiftUI

struct TimelinePlaceMiniMap: View {
    let location: TimelineLocationSnapshot?
    let needsReview: Bool

    var body: some View {
        ZStack {
            if let location, location.hasCoordinate {
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
                TimelineReviewBadge().padding(5)
            }
        }
    }
}
