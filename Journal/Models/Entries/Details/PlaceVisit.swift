//
//  PlaceVisitDetails.swift
//  Journal
//
//  Created by Alexandru Simedrea on 12/07/2026.
//

import Foundation
import SwiftData

nonisolated enum PlaceVisitReviewField: String, Codable, CaseIterable, Hashable, Sendable {
    case place
    case time
    case people
}

nonisolated struct PlaceVisitFieldReview: Codable, Hashable, Identifiable, Sendable {
    var field: PlaceVisitReviewField
    var reason: String

    var id: PlaceVisitReviewField { field }
}

@Model
final class PlaceVisitDetails {
    private var visitDescription: String?
    var place: Place?
    var location: Location?
    var placeRawText: String?
    var candidates: [LocationCandidate]
    var unresolvedPeople: [String]
    @Attribute(originalName: "fieldReviews")
    private var fieldReviewsData: Data?

    var fieldReviews: [PlaceVisitFieldReview] {
        get {
            PersistedJSON.decode(
                [PlaceVisitFieldReview].self,
                from: fieldReviewsData
            ) ?? []
        }
        set { fieldReviewsData = PersistedJSON.encode(newValue) }
    }

    init(
        description: String? = nil,
        place: Place? = nil,
        location: Location? = nil,
        placeRawText: String? = nil,
        candidates: [LocationCandidate] = [],
        unresolvedPeople: [String] = [],
        fieldReviews: [PlaceVisitFieldReview] = []
    ) {
        self.visitDescription = description
        self.place = place
        self.location = location ?? place?.location
        self.placeRawText = placeRawText
        self.candidates = candidates
        self.unresolvedPeople = unresolvedPeople
        self.fieldReviewsData = PersistedJSON.encode(fieldReviews)
    }

    var description: String? {
        get { visitDescription }
        set { visitDescription = newValue }
    }

    func review(for field: PlaceVisitReviewField) -> PlaceVisitFieldReview? {
        fieldReviews.first { $0.field == field }
    }
}
