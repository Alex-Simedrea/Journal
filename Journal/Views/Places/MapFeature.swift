//
//  PlaceMapFeature.swift
//  Journal
//

import MapKit
import SwiftUI

struct PlaceMapFeature: MapContent {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let systemImage: PlaceSystemImage
    let accuracyRadiusMeters: Double
    let radiusCenterCoordinate: CLLocationCoordinate2D?

    var body: some MapContent {
        if accuracyRadiusMeters > 0 {
            MapCircle(
                center: displayCoordinate,
                radius: accuracyRadiusMeters
            )
            .foregroundStyle(symbolColor.opacity(0.14))
            .stroke(symbolColor.opacity(0.62), lineWidth: 1.5)
        }

        Marker(
            name,
            systemImage: systemImage.rawValue,
            coordinate: displayCoordinate
        )
        .tint(symbolColor)
    }

    init(
        name: String,
        coordinate: CLLocationCoordinate2D,
        systemImage: PlaceSystemImage,
        accuracyRadiusMeters: Double = 0,
        radiusCenterCoordinate: CLLocationCoordinate2D? = nil
    ) {
        self.name = name
        self.coordinate = coordinate
        self.systemImage = systemImage
        self.accuracyRadiusMeters = max(accuracyRadiusMeters, 0)
        self.radiusCenterCoordinate = radiusCenterCoordinate
    }

    init(location: TimelineLocationSnapshot) {
        self.init(
            name: location.name,
            coordinate: location.coordinate,
            systemImage: location.systemImage,
            accuracyRadiusMeters: location.accuracyRadiusMeters,
            radiusCenterCoordinate: location.radiusCenterCoordinate
        )
    }

    private var displayCoordinate: CLLocationCoordinate2D {
        guard accuracyRadiusMeters > 0 else { return coordinate }
        return radiusCenterCoordinate ?? coordinate
    }

    private var symbolColor: Color {
        PlaceSymbols.symbol(for: systemImage).primary
    }
}

enum PlaceMapCamera {
    static func visibleDiameter(
        accuracyRadiusMeters: Double,
        minimum: Double
    ) -> Double {
        max(minimum, max(accuracyRadiusMeters, 0) * 2.6)
    }
}
