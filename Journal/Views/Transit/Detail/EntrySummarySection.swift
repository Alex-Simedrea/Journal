import MapKit
import SwiftData
import SwiftUI

struct TransitEntrySummarySection: View {
    let transitType: String
    let sourceOrganizationName: String?
    let sourceServiceIdentifier: String?
    let origin: String?
    let destination: String?
    let startTime: Date?
    let endTime: Date?
    let startTimeZoneIdentifier: String
    let endTimeZoneIdentifier: String
    let timeConfidence: TimeConfidence
    let peopleNames: [String]
    let createdAt: Date
    let entryKindReviewReason: String?
    let fieldReviews: [TransitFieldReview]

    var body: some View {
        Section("Details") {
            LabeledContent("Type", value: transitType)
            if let sourceOrganizationName {
                LabeledContent("Pass issuer", value: sourceOrganizationName)
            }
            if let sourceServiceIdentifier {
                LabeledContent("Service", value: sourceServiceIdentifier)
            }
            LabeledContent("Origin", value: origin ?? "Unresolved")
            LabeledContent("Destination", value: destination ?? "Unresolved")
            ZonedDateRow(
                title: "Started",
                date: startTime,
                timeZoneIdentifier: startTimeZoneIdentifier
            )
            ZonedDateRow(
                title: "Ended",
                date: endTime,
                timeZoneIdentifier: endTimeZoneIdentifier
            )
            LabeledContent("Time confidence", value: timeConfidence.title)

            if !peopleNames.isEmpty {
                LabeledContent("People", value: peopleNames.formatted())
            }

            LabeledContent("Created") {
                Text(
                    createdAt,
                    format: .dateTime
                        .day()
                        .month(.abbreviated)
                        .year()
                        .hour()
                        .minute()
                )
            }

            if entryKindReviewReason != nil || !fieldReviews.isEmpty {
                TransitFieldReviewList(
                    entryKindReviewReason: entryKindReviewReason,
                    reviews: fieldReviews
                )
            }
        }
    }
}

struct TransitFieldReviewList: View {
    let entryKindReviewReason: String?
    let reviews: [TransitFieldReview]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let entryKindReviewReason {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Entry type needs review")
                            .fontWeight(.semibold)
                        Text(entryKindReviewReason)
                            .font(.caption)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
            }
            ForEach(reviews) { review in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(review.field.title)
                            .fontWeight(.semibold)
                        Text(review.reason)
                            .font(.caption)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
            }
        }
        .foregroundStyle(.orange)
    }
}

private extension TransitReviewField {
    var title: LocalizedStringResource {
        switch self {
        case .transitType: "Transit type needs review"
        case .origin: "Origin needs review"
        case .destination: "Destination needs review"
        case .time: "Time needs review"
        case .people: "People need review"
        }
    }
}

extension TimeConfidence {
    var title: String {
        switch self {
        case .explicit: "Explicit"
        case .inferredFromHistory: "Inferred from day history"
        case .inferredNearOrigin: "Inferred near origin"
        case .inferredNearDestination: "Inferred near destination"
        case .unresolved: "Unresolved"
        case .manualOverride: "Manually corrected"
        }
    }
}
