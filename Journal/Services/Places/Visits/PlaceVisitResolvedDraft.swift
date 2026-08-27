import Foundation

nonisolated struct ResolvedPlaceVisitDraft {
    var description: String? = nil
    var place: Place?
    var location: Location?
    var placeRawText: String?
    var startTime: Date?
    var endTime: Date?
    var timeConfidence: TimeConfidence
    var people: [Person]
    var candidates: [LocationCandidate]
    var unresolvedPeople: [String]
    var fieldReviews: [PlaceVisitFieldReview]
    var entryKindReviewReason: String?

    var needsReview: Bool {
        entryKindReviewReason != nil || !fieldReviews.isEmpty
    }

    mutating func requireReview(
        _ field: PlaceVisitReviewField,
        reason: String
    ) {
        guard !fieldReviews.contains(where: { $0.field == field }) else {
            return
        }
        fieldReviews.append(
            PlaceVisitFieldReview(field: field, reason: reason)
        )
    }
}
