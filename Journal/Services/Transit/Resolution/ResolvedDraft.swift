//
//  TransitResolutionService.swift
//  Journal
//

import CoreLocation
import Foundation

struct ResolvedTransitDraft {
    var transitType: String
    var originPlace: Place?
    var originLocation: Location?
    var originRawText: String?
    var destinationPlace: Place?
    var destinationLocation: Location?
    var destinationRawText: String?
    var startTime: Date?
    var endTime: Date?
    var timeConfidence: TimeConfidence
    var people: [Person]
    var durationSource: DurationSource
    var originCandidates: [LocationCandidate]
    var destinationCandidates: [LocationCandidate]
    var unresolvedPeople: [String]
    var fieldReviews: [TransitFieldReview]
    var entryKindReviewReason: String? = nil

    var needsReview: Bool {
        entryKindReviewReason != nil || !fieldReviews.isEmpty
    }

    mutating func requireReview(
        _ field: TransitReviewField,
        reason: String
    ) {
        guard !fieldReviews.contains(where: { $0.field == field }) else {
            return
        }
        fieldReviews.append(TransitFieldReview(field: field, reason: reason))
    }
}
