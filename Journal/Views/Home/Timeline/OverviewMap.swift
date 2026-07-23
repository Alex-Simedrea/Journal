//
//  TimelineOverviewMap.swift
//  Journal
//

import MapKit
import SwiftUI

struct TimelineOverviewMap: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var position: MapCameraPosition = .automatic

    let data: TimelineOverviewData

    var body: some View {
        Map(position: $position) {
            ForEach(data.paths) { path in
                switch path.kind {
                case .transit(let transitType):
                    MapPolyline(coordinates: path.coordinates)
                        .stroke(
                            TransitPresentationCatalog
                                .presentation(for: transitType)
                                .color.opacity(0.82),
                            style: StrokeStyle(
                                lineWidth: 4,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                case .workout:
                    MapPolyline(coordinates: path.coordinates)
                        .stroke(
                            .black.opacity(0.48),
                            style: StrokeStyle(
                                lineWidth: 7,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    MapPolyline(coordinates: path.coordinates)
                        .stroke(
                            Color(hex: 0xB6FF00),
                            style: StrokeStyle(
                                lineWidth: 4,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }
            }

            ForEach(data.markers) { marker in
                PlaceMapFeature(
                    name: marker.name,
                    coordinate: marker.coordinate,
                    systemImage: marker.systemImage,
                    accuracyRadiusMeters: marker.accuracyRadiusMeters,
                    radiusCenterCoordinate: marker.radiusCenterCoordinate
                )
            }
        }
        .mapStyle(.standard)
        .onChange(of: data, initial: true) {
            position = .automatic
        }
        .frame(height: horizontalSizeClass == .regular ? 320 : 250)
        .clipShape(.rect(cornerRadius: 22))
        .accessibilityLabel("Map of the day’s places, transit, and workouts")
    }
}
