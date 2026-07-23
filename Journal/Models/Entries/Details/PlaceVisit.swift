//
//  PlaceVisitDetails.swift
//  Journal
//
//  Created by Alexandru Simedrea on 12/07/2026.
//

import Foundation
import SwiftData

enum PlaceVisitReviewField: String, Codable, CaseIterable, Hashable {
    case place
    case time
    case people
}

struct PlaceVisitFieldReview: Codable, Hashable, Identifiable {
    var field: PlaceVisitReviewField
    var reason: String

    var id: PlaceVisitReviewField { field }
}

@Model
final class PlaceVisitDetails {
    var place: Place?
    var location: Location?
    var placeRawText: String?
    var candidates: [LocationCandidate]
    var unresolvedPeople: [String]
    var fieldReviews: [PlaceVisitFieldReview]

    init(
        place: Place? = nil,
        location: Location? = nil,
        placeRawText: String? = nil,
        candidates: [LocationCandidate] = [],
        unresolvedPeople: [String] = [],
        fieldReviews: [PlaceVisitFieldReview] = []
    ) {
        self.place = place
        self.location = location ?? place?.location
        self.placeRawText = placeRawText
        self.candidates = candidates
        self.unresolvedPeople = unresolvedPeople
        self.fieldReviews = fieldReviews
    }

    func review(for field: PlaceVisitReviewField) -> PlaceVisitFieldReview? {
        fieldReviews.first { $0.field == field }
    }
}
