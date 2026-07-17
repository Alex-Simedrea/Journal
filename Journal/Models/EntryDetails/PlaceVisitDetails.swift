//
//  PlaceVisitDetails.swift
//  Journal
//
//  Created by Alexandru Simedrea on 12/07/2026.
//

import Foundation
import SwiftData

@Model
final class PlaceVisitDetails {
    var place: Place?
    var placeRawText: String?

    init(
        place: Place? = nil,
        placeRawText: String? = nil
    ) {
        self.place = place
        self.placeRawText = placeRawText
    }
}
