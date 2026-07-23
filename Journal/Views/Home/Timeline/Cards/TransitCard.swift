import MapKit
import Photos
import SwiftUI

struct TimelineTransitCard: View {
    let occurrence: TimelineOccurrence

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 6
            let typeWidth = (proxy.size.width - gap) * 0.42
            HStack(spacing: gap) {
                TimelineTransitTypeTile(occurrence: occurrence)
                    .frame(width: typeWidth)
                TimelinePlacesTile(
                    origin: occurrence.snapshot.originLocation,
                    originName: occurrence.origin,
                    destination: occurrence.snapshot.destinationLocation,
                    destinationName: occurrence.destination,
                    needsReview: occurrence.snapshot.reviews.contains {
                        $0.target == .origin || $0.target == .destination
                    }
                )
            }
        }
        .frame(height: 50)
    }
}

struct TimelineTransitTypeTile: View {
    let occurrence: TimelineOccurrence

    private var presentation: TransitPresentation {
        TransitPresentationCatalog.presentation(for: occurrence.transitType)
    }

    var body: some View {
        HStack(spacing: 8) {
            TransitPresentationIcon(
                presentation: presentation,
                size: 22,
                weight: .semibold
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(occurrence.transitType)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                TimelineTransitMetrics(occurrence: occurrence)
            }
        }
        .foregroundStyle(presentation.foregroundColor)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(presentation.color, in: .rect(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            if occurrence.snapshot.reviews.contains(where: {
                $0.target == .transitType
            }) {
                TimelineReviewBadge().padding(5)
            }
        }
    }
}

struct TimelineTransitMetrics: View {
    let occurrence: TimelineOccurrence

    var body: some View {
        HStack(spacing: 3) {
            if let distance = occurrence.snapshot.transitDistanceMeters {
                Text(
                    Measurement(value: distance, unit: UnitLength.meters),
                    format: .measurement(width: .abbreviated)
                )
            }
            if let start = occurrence.startTime,
                let end = occurrence.endTime,
                end > start
            {
                Text("•")
                Text(
                    end.timeIntervalSince(start),
                    format: .compactDuration
                )
            }
        }
        .font(.footnote.weight(.medium))
        .opacity(0.8)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}
