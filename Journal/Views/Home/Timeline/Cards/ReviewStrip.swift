import MapKit
import Photos
import SwiftUI

struct TimelineUnmatchedReviewStrip: View {
    let occurrence: TimelineOccurrence

    private var reviews: [TimelineReviewSnapshot] {
        let mapped: Set<TimelineReviewTarget> =
            switch occurrence.kind {
            case .transit: [.transitType, .origin, .destination, .time]
            case .placeVisit: [.place, .people, .time]
            case .workout: [.place, .origin, .destination]
            case .wakeUp: []
            }
        return occurrence.snapshot.reviews.filter {
            !mapped.contains($0.target)
        }
    }

    var body: some View {
        if !reviews.isEmpty {
            HStack(spacing: 6) {
                TimelineReviewBadge()
                Text(reviews.map(\.target.title).formatted())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        }
    }
}

extension TimelineReviewTarget {
    fileprivate var title: String {
        switch self {
        case .entryKind: String(localized: "Entry type needs review")
        case .transitType: String(localized: "Transit type needs review")
        case .origin: String(localized: "Origin needs review")
        case .destination: String(localized: "Destination needs review")
        case .place: String(localized: "Place needs review")
        case .time: String(localized: "Time needs review")
        case .people: String(localized: "People need review")
        }
    }
}
