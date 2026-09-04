import MapKit
import Photos
import SwiftUI

enum TimelineCompactMovementStyle {
    case transit(TransitPresentation)
    case workout(systemImageName: String)
}

struct TimelineCompactMovementRow: View {
    let title: String
    let style: TimelineCompactMovementStyle
    let organizationName: String?
    let serviceIdentifier: String?
    let distanceMeters: Double?
    let activeEnergyKilocalories: Double?
    let photoReferences: [PhotoReference]
    let startTime: Date?
    let endTime: Date?
    let people: [TimelinePersonSnapshot]
    let showsReviewBadge: Bool
    let reviewCandidateID: UUID?
    let onAcceptCandidate: (UUID) -> Void
    let onDismissCandidate: (UUID) -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onTap) {
                HStack(
                    spacing: TimelineRulerMetrics.compactEntryContentSpacing
                ) {
                    TimelineCompactMovementBadge(style: style)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(summary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        if let metrics {
                            Text(metrics)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: TimelineRulerMetrics.compactEntryHeight,
                        maxHeight: TimelineRulerMetrics.compactEntryHeight,
                        alignment: .leading
                    )

                    if !people.isEmpty {
                        TimelinePeopleAvatarStack(people: people)
                    }

                    if !photoReferences.isEmpty {
                        TimelineCompactMovementPhotos(references: photoReferences)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens entry details")

            if let reviewCandidateID {
                TimelineTransitQuickReviewButton(
                    systemImage: "xmark",
                    foregroundColor: .gray,
                    backgroundColor: .gray.opacity(0.2),
                    accessibilityLabel: "Dismiss suggested transit",
                    action: { onDismissCandidate(reviewCandidateID) }
                )
                TimelineTransitQuickReviewButton(
                    systemImage: "checkmark",
                    foregroundColor: .white,
                    backgroundColor: .blue,
                    accessibilityLabel: "Accept suggested transit",
                    action: { onAcceptCandidate(reviewCandidateID) }
                )
            }

            if showsReviewBadge {
                ReviewBadge(size: 17)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: TimelineRulerMetrics.compactEntryHeight,
            alignment: .leading
        )
    }

    private var summary: AttributedString {
        var result = AttributedString(title)
        result.font = .callout.weight(.semibold)

        if let organizationName = normalized(organizationName) {
            var organization = AttributedString(" \(organizationName)")
            organization.font = .callout.weight(.regular)
            result.append(organization)
        }

        if let serviceIdentifier = normalized(serviceIdentifier) {
            var service = AttributedString(" • \(serviceIdentifier)")
            service.font = .callout.weight(.regular)
            result.append(service)
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
        if let activeEnergyKilocalories {
            values.append("\(activeEnergyKilocalories.formatted(.number.precision(.fractionLength(0)))) kcal")
        }
        return values.isEmpty ? nil : values.joined(separator: " • ")
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct TimelineTransitQuickReviewButton: View {
    let systemImage: String
    let foregroundColor: Color
    let backgroundColor: Color
    let accessibilityLabel: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(width: 24, height: 24)
                .background(backgroundColor, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct TimelineCompactMovementBadge: View {
    let style: TimelineCompactMovementStyle

    var body: some View {
        Group {
            switch style {
            case .transit(let presentation):
                TransitPresentationIcon(
                    presentation: presentation,
                    size: TimelineRulerMetrics.compactEntryIconSize,
                    weight: .semibold
                )
                .foregroundStyle(presentation.foregroundColor)
            case .workout(let systemImageName):
                FixedSizeSymbol(
                    systemName: systemImageName,
                    size: TimelineRulerMetrics.compactEntryIconSize,
                    weight: .semibold
                )
                .foregroundStyle(.black)
            }
        }
        .frame(
            width: TimelineRulerMetrics.compactEntryBadgeSize,
            height: TimelineRulerMetrics.compactEntryBadgeSize
        )
        .background(backgroundColor.gradient, in: .circle)
        .accessibilityHidden(true)
    }

    private var backgroundColor: Color {
        switch style {
        case .transit(let presentation): presentation.color
        case .workout: Color(hex: 0xB6FF00)
        }
    }
}

struct TimelineCompactMovementPhotos: View {
    let references: [PhotoReference]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(references.prefix(2).enumerated()), id: \.element.id) { index, reference in
                TimelinePhotoThumbnail(reference: reference)
                    .frame(
                        width: TimelineRulerMetrics.compactEntryHeight,
                        height: TimelineRulerMetrics.compactEntryHeight
                    )
                    .overlay {
                        if index == 1, references.count > 2 {
                            ZStack {
                                Color.black.opacity(0.45)
                                Text("+\(references.count - 2)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .clipShape(.rect(cornerRadius: 10))
            }
        }
        .accessibilityLabel("\(references.count) photos")
    }
}

struct TimelineTransitPseudoPlaceRow: View {
    let name: String
    let systemImage: PlaceSystemImage
    var onAddPlaceVisit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: TimelineRulerMetrics.compactEntryContentSpacing) {
            FixedSizePlaceSymbol(systemImage: systemImage, size: 18)
                .accessibilityHidden(true)

            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if let onAddPlaceVisit {
                Button("Add Place Visit", action: onAddPlaceVisit)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.blue)
                    .buttonStyle(.plain)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, 10)
                    .accessibilityLabel("Add place visit at \(name)")
            }

            Spacer(minLength: 0)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: TimelineRulerMetrics.pseudoPlaceHeight,
            alignment: .leading
        )
        .accessibilityElement(children: .contain)
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
                    needsReview: false
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

            Spacer(minLength: 0)

            if occurrence.needsReview {
                ReviewBadge(size: 17)
            }
        }
        .foregroundStyle(presentation.foregroundColor)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(presentation.color, in: .rect(cornerRadius: 16))
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
