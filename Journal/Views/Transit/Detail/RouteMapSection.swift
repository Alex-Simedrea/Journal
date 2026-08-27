import MapKit
import SwiftData
import SwiftUI

struct TransitRouteMapSection: View {
    let transitType: String
    let recordedRoute: [RecordedRoutePoint]
    let origin: Location?
    let destination: Location?

    var body: some View {
        if origin != nil || destination != nil || routeCoordinates.count > 1 {
            Section("Route") {
                Map(initialPosition: .automatic) {
                    if routeCoordinates.count > 1 {
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(
                                TransitPresentationCatalog.presentation(
                                    for: transitType
                                ).color.opacity(0.82),
                                style: StrokeStyle(
                                    lineWidth: 4,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                    }

                    if let origin {
                        Marker(
                            "Origin",
                            systemImage: "circle.fill",
                            coordinate: origin.coordinate
                        )
                        .tint(.blue)
                    }

                    if let destination {
                        Marker(
                            "Destination",
                            systemImage: "flag.fill",
                            coordinate: destination.coordinate
                        )
                        .tint(.red)
                    }
                }
                .mapStyle(
                    JournalMapDisplayStylePolicy.mapStyle(
                        for: [origin, destination]
                            .compactMap { $0?.coordinate }
                    )
                )
                .frame(height: 220)
                .clipShape(.rect(cornerRadius: 12))
            }
        }
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        TransitRouteGeometry.coordinates(
            recordedRoute: recordedRoute,
            origin: origin?.coordinate,
            destination: destination?.coordinate,
            bendPositive: true
        )
    }
}
