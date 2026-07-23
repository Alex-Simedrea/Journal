//
//  Place.swift
//  Journal
//
//  Created by Alexandru Simedrea on 11/07/2026.
//

import Foundation
import SwiftData

@Model
class Place {
    @Attribute(.unique) var id: UUID

    var name: String
    var aliases: [String]  // spellings the llm identified
    var systemImage: PlaceSystemImage = PlaceSystemImage.mappin

    var location: Location
    var accuracyRadiusMeters: Double = 0

    var createdAt: Date

    init(
        id: UUID,
        name: String,
        aliases: [String],
        location: Location,
        systemImage: PlaceSystemImage,
        createdAt: Date,
        accuracyRadiusMeters: Double = 0
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.location = location
        self.systemImage = systemImage
        self.createdAt = createdAt
        self.accuracyRadiusMeters = accuracyRadiusMeters
    }

    convenience init(
        name: String,
        location: Location,
        systemImage: PlaceSystemImage = .mappin,
        accuracyRadiusMeters: Double = 0
    ) {
        self.init(
            id: UUID(),
            name: name,
            aliases: [],
            location: location,
            systemImage: systemImage,
            createdAt: .now,
            accuracyRadiusMeters: accuracyRadiusMeters
        )
    }
}
