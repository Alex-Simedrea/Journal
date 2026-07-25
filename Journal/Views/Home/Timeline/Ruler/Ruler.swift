//
//  TimelineRuler.swift
//  Journal
//

import SwiftUI

struct TimelineRulerSequence: View {
    let rows: [TimelineRow]
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            TimelineRulerEndCap()

            ForEach(rows) { row in
                TimelineRulerRow(
                    row: row,
                    onSelect: onSelect
                )
            }

            TimelineRulerEndCap()
        }
        .overlayPreferenceValue(TimelineCardBoundsKey.self) { anchors in
            TimelineRulerOverlay(cardBounds: anchors)
        }
        .padding(.horizontal)
    }
}

private struct TimelineRulerEndCap: View {
    var body: some View {
        Color.clear.frame(height: TimelineRulerMetrics.endCapHeight)
    }
}

private struct TimelineRulerActiveBounds {
    let anchor: Anchor<CGRect>
    let rangeStyle: TimelineRulerActiveRangeStyle
}

private enum TimelineRulerActiveRangeStyle {
    case interval(expansion: CGFloat)
    case moment(radius: CGFloat)
    case boundaryConnection
    case sharedBoundaryConnection
    case previousBoundaryConnection
}

private struct TimelineCardBoundsKey: PreferenceKey {
    static let defaultValue: [TimelineRulerActiveBounds] = []

    static func reduce(
        value: inout [TimelineRulerActiveBounds],
        nextValue: () -> [TimelineRulerActiveBounds]
    ) {
        value.append(contentsOf: nextValue())
    }
}

private struct TimelineRulerOverlay: View {
    let cardBounds: [TimelineRulerActiveBounds]

    var body: some View {
        GeometryReader { proxy in
            TimelineRulerTrack(
                activeRanges: cardBounds.map { activeBounds in
                    let bounds = proxy[activeBounds.anchor]
                    return switch activeBounds.rangeStyle {
                    case .interval(let expansion):
                        (bounds.minY - expansion)...(bounds.maxY + expansion)
                    case .moment(let radius):
                        (bounds.midY - radius)...(bounds.midY + radius)
                    case .boundaryConnection:
                        TimelineRulerMetrics.boundaryConnectionRange(in: bounds)
                    case .sharedBoundaryConnection:
                        TimelineRulerMetrics.sharedBoundaryConnectionRange(
                            in: bounds
                        )
                    case .previousBoundaryConnection:
                        TimelineRulerMetrics.previousBoundaryConnectionRange(
                            in: bounds
                        )
                    }
                }
            )
            .frame(width: TimelineRulerMetrics.trackWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TimelineRulerRow: View {
    let row: TimelineRow
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !row.startBoundaryRenderedByPrevious {
                TimelineRulerGap(relationship: row.relationshipToPrevious)
            }

            switch row.occurrence.kind {
            case .wakeUp:
                TimelineWakeUpRulerContent(occurrence: row.occurrence)
            case .transit:
                if let presentation = row.transitPresentation {
                    TimelineTransitRulerContent(
                        row: row,
                        presentation: presentation,
                        onSelect: onSelect
                    )
                }
            case .placeVisit, .workout:
                TimelineIntervalRulerContent(
                    row: row,
                    onSelect: onSelect
                )
            }
        }
    }
}

private struct TimelineTransitRulerContent: View {
    let row: TimelineRow
    let presentation: TimelineTransitRowPresentation
    let onSelect: (UUID) -> Void

    private var showsStartLabel: Bool {
        !row.startBoundaryRenderedByPrevious
            && row.relationshipToPrevious != .contiguous
            && row.occurrence.visibleStartTime != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if presentation.origin.showsPseudoEntry {
                if showsStartLabel,
                   let start = row.occurrence.visibleStartTime {
                    TimelineTransitOriginBoundaryBlock(
                        boundary: presentation.origin,
                        date: start,
                        timeZoneIdentifier: row.occurrence.timeZoneIdentifier,
                        needsTimeReview: row.occurrence.reviewsTime
                    )
                } else {
                    TimelineTransitPseudoRulerRow(
                        boundary: presentation.origin
                    )
                    .anchorPreference(
                        key: TimelineCardBoundsKey.self,
                        value: .bounds,
                        transform: {
                            [
                                TimelineRulerActiveBounds(
                                    anchor: $0,
                                    rangeStyle: row.relationshipToPrevious
                                        == .contiguous
                                        ? .previousBoundaryConnection
                                        : .interval(expansion: 0)
                                )
                            ]
                        }
                    )
                }
            } else if showsStartLabel,
                      let start = row.occurrence.visibleStartTime {
                TimelineBoundaryLabel(
                    date: start,
                    timeZoneIdentifier: row.occurrence.timeZoneIdentifier,
                    showsTimeZoneChange: false,
                    needsReview: row.occurrence.reviewsTime
                )
            }

            TimelineCompactTransitRulerRow(
                occurrence: row.occurrence,
                showsReviewBadge: presentation.showsReviewBadge,
                onTap: selectTransit
            )

            if let end = row.occurrence.visibleEndTime {
                if presentation.destination.showsPseudoEntry {
                    TimelineTransitDestinationBoundaryBlock(
                        boundary: presentation.destination,
                        date: end,
                        timeZoneIdentifier: row.occurrence.changesTimeZone
                            ? row.occurrence.endTimeZoneIdentifier
                            : row.occurrence.timeZoneIdentifier,
                        showsTimeZoneChange: row.occurrence.changesTimeZone,
                        needsTimeReview: row.endBoundaryNeedsReview
                    )
                } else {
                    TimelineBoundaryLabel(
                        date: end,
                        timeZoneIdentifier: row.occurrence.changesTimeZone
                            ? row.occurrence.endTimeZoneIdentifier
                            : row.occurrence.timeZoneIdentifier,
                        showsTimeZoneChange: row.occurrence.changesTimeZone,
                        needsReview: row.endBoundaryNeedsReview
                    )
                }
            }
        }
    }

    private func selectTransit() {
        onSelect(row.occurrence.entryID)
    }
}

private struct TimelineTransitOriginBoundaryBlock: View {
    let boundary: TimelineTransitBoundaryPresentation
    let date: Date
    let timeZoneIdentifier: String
    let needsTimeReview: Bool

    var body: some View {
        VStack(spacing: 0) {
            TimelineTransitPseudoRulerRow(boundary: boundary)
            TimelineBoundaryLabel(
                date: date,
                timeZoneIdentifier: timeZoneIdentifier,
                showsTimeZoneChange: false,
                needsReview: needsTimeReview
            )
        }
        .anchorPreference(
            key: TimelineCardBoundsKey.self,
            value: .bounds,
            transform: {
                [
                    TimelineRulerActiveBounds(
                        anchor: $0,
                        rangeStyle: .boundaryConnection
                    )
                ]
            }
        )
    }
}

private struct TimelineTransitDestinationBoundaryBlock: View {
    let boundary: TimelineTransitBoundaryPresentation
    let date: Date
    let timeZoneIdentifier: String
    let showsTimeZoneChange: Bool
    let needsTimeReview: Bool

    var body: some View {
        VStack(spacing: 0) {
            TimelineBoundaryLabel(
                date: date,
                timeZoneIdentifier: timeZoneIdentifier,
                showsTimeZoneChange: showsTimeZoneChange,
                needsReview: needsTimeReview
            )

            if let followingStart = boundary.followingTransitStart {
                TimelineTransitPseudoRulerRow(boundary: boundary)
                TimelineBoundaryLabel(
                    date: followingStart.date,
                    timeZoneIdentifier: followingStart.timeZoneIdentifier,
                    showsTimeZoneChange: false,
                    needsReview: followingStart.needsReview
                )
            } else {
                TimelineTransitPseudoRulerRow(boundary: boundary)
            }
        }
        .anchorPreference(
            key: TimelineCardBoundsKey.self,
            value: .bounds,
            transform: {
                [
                    TimelineRulerActiveBounds(
                        anchor: $0,
                        rangeStyle: boundary.followingTransitStart == nil
                            ? .boundaryConnection
                            : .sharedBoundaryConnection
                    )
                ]
            }
        )
    }
}

private struct TimelineTransitPseudoRulerRow: View {
    let boundary: TimelineTransitBoundaryPresentation

    var body: some View {
        HStack(
            spacing: TimelineRulerMetrics.cardSpacing
        ) {
            Color.clear
                .frame(width: TimelineRulerMetrics.trackWidth)

            TimelineTransitPseudoPlaceRow(
                name: boundary.name,
                systemImage: boundary.systemImage,
                needsReview: boundary.needsReview
            )
        }
    }
}

private struct TimelineCompactTransitRulerRow: View {
    let occurrence: TimelineOccurrence
    let showsReviewBadge: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(
            spacing: TimelineRulerMetrics.cardSpacing
        ) {
            Color.clear
                .frame(width: TimelineRulerMetrics.trackWidth)

            TimelineCompactTransitRow(
                transitType: occurrence.transitType,
                organizationName: occurrence.snapshot
                    .transitSourceOrganizationName,
                serviceIdentifier: occurrence.snapshot
                    .transitSourceServiceIdentifier,
                distanceMeters: occurrence.snapshot.transitDistanceMeters,
                startTime: occurrence.startTime,
                endTime: occurrence.endTime,
                people: occurrence.snapshot.people,
                showsReviewBadge: showsReviewBadge,
                onTap: onTap
            )
        }
    }
}

private struct TimelineIntervalRulerContent: View {
    let row: TimelineRow
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if row.relationshipToPrevious != .contiguous,
               let start = row.occurrence.visibleStartTime {
                TimelineBoundaryLabel(
                    date: start,
                    timeZoneIdentifier: row.occurrence.timeZoneIdentifier,
                    showsTimeZoneChange: false,
                    needsReview: row.occurrence.reviewsTime
                )
            }

            HStack(
                alignment: .top,
                spacing: TimelineRulerMetrics.cardSpacing
            ) {
                Color.clear
                    .frame(width: TimelineRulerMetrics.trackWidth)

                TimelineEntryCard(
                    occurrence: row.occurrence,
                    onTap: { onSelect(row.occurrence.entryID) }
                )
                .anchorPreference(
                    key: TimelineCardBoundsKey.self,
                    value: .bounds,
                    transform: {
                        [
                            TimelineRulerActiveBounds(
                                anchor: $0,
                                rangeStyle: .interval(
                                    expansion: TimelineRulerMetrics
                                        .activeRangeExpansion
                                )
                            )
                        ]
                    }
                )
            }

            if let end = row.occurrence.visibleEndTime {
                TimelineBoundaryLabel(
                    date: end,
                    timeZoneIdentifier: row.occurrence.changesTimeZone
                        ? row.occurrence.endTimeZoneIdentifier
                        : row.occurrence.timeZoneIdentifier,
                    showsTimeZoneChange: row.occurrence.changesTimeZone,
                    needsReview: row.endBoundaryNeedsReview
                )
            }
        }
    }
}

private struct TimelineWakeUpRulerContent: View {
    let occurrence: TimelineOccurrence

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: TimelineRulerMetrics.trackWidth)

            TimelineTimestampText(
                date: occurrence.sortTime,
                timeZoneIdentifier: occurrence.timeZoneIdentifier
            )
                .frame(
                    width: TimelineRulerMetrics.wakeUpTimestampWidth,
                    alignment: .trailing
                )

            TimelineEntryCard(occurrence: occurrence, onTap: {})
                .padding(.leading, TimelineRulerMetrics.wakeUpContentSpacing)
                .anchorPreference(
                    key: TimelineCardBoundsKey.self,
                    value: .bounds,
                    transform: {
                        [
                            TimelineRulerActiveBounds(
                                anchor: $0,
                                rangeStyle: .moment(
                                    radius: TimelineRulerMetrics
                                        .wakeUpActiveRangeRadius
                                )
                            )
                        ]
                    }
                )
        }
    }
}

private struct TimelineRulerGap: View {
    let relationship: TimelinePreviousRelationship

    var body: some View {
        Color.clear.frame(height: height)
    }

    private var height: CGFloat {
        switch relationship {
        case .first, .contiguous: 0
        case .overlap: 16
        case .gap(let duration):
            TimelineRulerMetrics.separateEntryGap(duration: duration)
        }
    }

}

private struct TimelineBoundaryLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    let date: Date
    let timeZoneIdentifier: String
    let showsTimeZoneChange: Bool
    let needsReview: Bool

    var body: some View {
        HStack(spacing: TimelineRulerMetrics.timestampSpacing) {
            Color.clear
                .frame(width: TimelineRulerMetrics.trackWidth)

            TimelineTimestampText(
                date: date,
                timeZoneIdentifier: timeZoneIdentifier
            )

            if showsTimeZoneChange {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                Text(
                    (TimeZone(identifier: timeZoneIdentifier) ?? .current)
                        .abbreviation(for: date) ?? timeZoneIdentifier
                )
            }

            if needsReview {
                ReviewBadge(size: 17)
            }

            Spacer()
        }
        .font(.caption)
        .foregroundStyle(TimelineRulerPalette.timestamp(colorScheme: colorScheme))
        .frame(height: 28)
        .accessibilityElement(children: .combine)
    }
}

private struct TimelineTimestampText: View {
    @Environment(\.colorScheme) private var colorScheme
    let date: Date
    let timeZoneIdentifier: String

    var body: some View {
        Text(date, format: .dateTime.hour().minute())
            .environment(
                \.timeZone,
                TimeZone(identifier: timeZoneIdentifier) ?? .current
            )
            .font(.caption)
            .foregroundStyle(
                TimelineRulerPalette.timestamp(colorScheme: colorScheme)
            )
            .monospacedDigit()
    }
}

private struct TimelineRulerTrack: View {
    @Environment(\.colorScheme) private var colorScheme
    let activeRanges: [ClosedRange<CGFloat>]

    var body: some View {
        Canvas { context, size in
            var y = TimelineRulerMetrics.firstTickOffset
            while y < size.height {
                let style = TimelineRulerMetrics.style(
                    distanceFromActiveRange: distanceFromActiveRange(at: y)
                )
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: style.length, y: y))
                context.stroke(
                    path,
                    with: .color(
                        TimelineRulerPalette.line(
                            level: style.level,
                            colorScheme: colorScheme
                        )
                    ),
                    style: StrokeStyle(
                        lineWidth: TimelineRulerMetrics.lineWidth,
                        lineCap: .butt
                    )
                )
                y += TimelineRulerMetrics.tickPitch
            }
        }
        .accessibilityHidden(true)
    }

    private func distanceFromActiveRange(at y: CGFloat) -> CGFloat {
        activeRanges.reduce(.greatestFiniteMagnitude) { distance, range in
            if range.contains(y) {
                return 0
            }
            return min(
                distance,
                y < range.lowerBound
                    ? range.lowerBound - y
                    : y - range.upperBound
            )
        }
    }
}
