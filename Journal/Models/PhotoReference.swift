//
//  PhotoReference.swift
//  Journal
//
//  Created by Alexandru Simedrea on 12/07/2026.
//

import Foundation

nonisolated struct PhotoReference: Codable, Hashable, Identifiable, Sendable {
    var assetLocalIdentifier: String
    var addedAt: Date

    var id: String { assetLocalIdentifier }

    init(
        assetLocalIdentifier: String,
        addedAt: Date = .now
    ) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.addedAt = addedAt
    }
}
