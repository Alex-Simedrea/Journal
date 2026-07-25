import MapKit
import Photos
import SwiftUI

struct TimelineCompactTransitRow: View {
    let transitType: String
    let organizationName: String?
    let serviceIdentifier: String?
    let distanceMeters: Double?
    let startTime: Date?
    let endTime: Date?
    let people: [TimelinePersonSnapshot]
    let showsReviewBadge: Bool
    let onTap: () -> Void

    private var presentation: TransitPresentation {
        TransitPresentationCatalog.presentation(for: transitType)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TimelineRulerMetrics.compactEntryContentSpacing) {
                TimelineCompactTransitBadge(presentation: presentation)

                Text(summary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsReviewBadge {
                    ReviewBadge(size: 17)
                }

                if !people.isEmpty {
                    TimelinePeopleAvatarStack(people: people)
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: TimelineRulerMetrics.compactEntryHeight,
                alignment: .leading
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens transit details")
    }

    private var summary: AttributedString {
        var result = AttributedString(transitType)
        result.font = .headline.weight(.semibold)

        if let organizationName = normalized(organizationName) {
            var organization = AttributedString(" \(organizationName)")
            organization.font = .headline.weight(.regular)
            result.append(organization)
        }

        if let serviceIdentifier = normalized(serviceIdentifier) {
            var service = AttributedString(" • \(serviceIdentifier)")
            service.font = .headline.weight(.regular)
            result.append(service)
        }

        if let metrics {
            var metricText = AttributedString("  \(metrics)")
            metricText.font = .subheadline.weight(.medium)
            metricText.foregroundColor = .secondary
            result.append(metricText)
        }

        return result
    }

    private var metrics: String? {
        var values: [String] = []
        if let distanceMeters {
            values.append(
                Measurement(
                    value: distanceMeters,
                    unit: UnitLength.meters
                ).formatted(.measurement(width: .abbreviated))
            )
        }
        if let startTime, let endTime, endTime > startTime {
            values.append(
                endTime.timeIntervalSince(startTime)
                    .formatted(.compactDuration)
            )
        }
        return values.isEmpty ? nil : values.joined(separator: " • ")
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct TimelineCompactTransitBadge: View {
    let presentation: TransitPresentation

    var body: some View {
        TransitPresentationIcon(
            presentation: presentation,
            size: TimelineRulerMetrics.compactEntryIconSize,
            weight: .semibold
        )
        .foregroundStyle(presentation.foregroundColor)
        .frame(
            width: TimelineRulerMetrics.compactEntryBadgeSize,
            height: TimelineRulerMetrics.compactEntryBadgeSize
        )
        .background(presentation.color.gradient, in: .circle)
        .accessibilityHidden(true)
    }
}

struct TimelineTransitPseudoPlaceRow: View {
    let name: String
    let systemImage: PlaceSystemImage
    let needsReview: Bool

    var body: some View {
        HStack(spacing: TimelineRulerMetrics.compactEntryContentSpacing) {
            TimelineTransitPseudoPlaceBadge(systemImage: systemImage)

            Text(name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)

            if needsReview {
                ReviewBadge(size: 17)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: TimelineRulerMetrics.compactEntryHeight,
            alignment: .leading
        )
        .accessibilityElement(children: .combine)
    }
}

struct TimelineTransitPseudoPlaceBadge: View {
    let systemImage: PlaceSystemImage

    var body: some View {
        let symbol = PlaceSymbols.symbol(for: systemImage)
        Image(systemName: symbol.systemImage.rawValue)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(
                width: TimelineRulerMetrics.compactEntryIconSize,
                height: TimelineRulerMetrics.compactEntryIconSize
            )
            .frame(
                width: TimelineRulerMetrics.compactEntryBadgeSize,
                height: TimelineRulerMetrics.compactEntryBadgeSize
            )
            .background(symbol.secondary.gradient, in: .circle)
            .accessibilityHidden(true)
    }
}

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
                ReviewBadge(size: 17).padding(5)
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
