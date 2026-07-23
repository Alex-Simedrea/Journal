import MapKit
import SwiftData
import SwiftUI

struct TransitRouteMapSection: View {
    let origin: Location?
    let destination: Location?

    var body: some View {
        if origin != nil || destination != nil {
            Section("Route") {
                Map(initialPosition: .automatic) {
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
                .frame(height: 220)
                .clipShape(.rect(cornerRadius: 12))
            }
        }
    }
}
