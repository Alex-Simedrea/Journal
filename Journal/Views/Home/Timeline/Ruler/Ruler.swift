//
//  TimelineRuler.swift
//  Journal
//

import SwiftUI

struct TimelineRulerSequence: View {
    let rows: [TimelineRow]
    let pendingAutomationCandidateIDsByEntryID: [UUID: UUID]
    let onSelect: (UUID) -> Void
    let onAcceptCandidateEntry: (UUID, UUID) -> Void
    let onDismissCandidate: (UUID) -> Void
    let onAddTransit: (TimelineTransitGapID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            TimelineRulerEndCap()

            ForEach(rows) { row in
                TimelineRulerRow(
                    row: row,
                    reviewCandidateID:
                        pendingAutomationCandidateIDsByEntryID[
                            row.occurrence.entryID
                        ],
                    onSelect: onSelect,
                    onAcceptCandidateEntry: onAcceptCandidateEntry,
                    onDismissCandidate: onDismissCandidate,
                    onAddTransit: onAddTransit
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
    let reviewCandidateID: UUID?
    let onSelect: (UUID) -> Void
    let onAcceptCandidateEntry: (UUID, UUID) -> Void
    let onDismissCandidate: (UUID) -> Void
    let onAddTransit: (TimelineTransitGapID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !row.startBoundaryRenderedByPrevious {
                TimelineRulerGap(
                    relationship: row.relationshipToPrevious,
                    transitGap: row.transitGap,
                    separatesDistinctContiguousBoundary:
                        row.presentsDistinctContiguousTransitStart,
                    onAddTransit: onAddTransit
                )
            }

            switch row.occurrence.kind {
            case .wakeUp:
                TimelineWakeUpRulerContent(occurrence: row.occurrence)
            case .transit:
                if let presentation = row.transitPresentation {
                    TimelineTransitRulerContent(
                        row: row,
                        presentation: presentation,
                        reviewCandidateID: reviewCandidateID,
                        onSelect: onSelect,
                        onAcceptCandidateEntry: onAcceptCandidateEntry,
                        onDismissCandidate: onDismissCandidate
                    )
                }
            case .workout:
                if let presentation = row.transitPresentation {
                    TimelineTransitRulerContent(
                        row: row,
                        presentation: presentation,
                        reviewCandidateID: nil,
                        onSelect: onSelect,
                        onAcceptCandidateEntry: onAcceptCandidateEntry,
                        onDismissCandidate: onDismissCandidate
                    )
                } else {
                    TimelineIntervalRulerContent(
                        row: row,
                        onSelect: onSelect
                    )
                }
            case .placeVisit:
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
    let reviewCandidateID: UUID?
    let onSelect: (UUID) -> Void
    let onAcceptCandidateEntry: (UUID, UUID) -> Void
    let onDismissCandidate: (UUID) -> Void

    private var showsStartLabel: Bool {
        !row.startBoundaryRenderedByPrevious
            && row.occurrence.visibleStartTime != nil
            && (row.relationshipToPrevious != .contiguous
                || row.presentsDistinctContiguousTransitStart)
    }

    var body: some View {
        VStack(spacing: 0) {
            if presentation.origin.showsPseudoEntry {
                if showsStartLabel,
                   let start = row.occurrence.visibleStartTime {
                    TimelineTransitOriginBoundaryBlock(
                        boundary: presentation.origin,
                        date: start,
                        timeZoneIdentifier: row.occurrence.timeZoneIdentifier
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
                    needsReview: false
                )
            }

            TimelineCompactMovementRulerRow(
                occurrence: row.occurrence,
                showsReviewBadge: presentation.showsReviewBadge,
                reviewCandidateID: presentation.showsReviewBadge
                    ? reviewCandidateID
                    : nil,
                onAcceptCandidateEntry: onAcceptCandidateEntry,
                onDismissCandidate: onDismissCandidate,
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
                        showsTimeZoneChange: row.occurrence.changesTimeZone
                    )
                } else {
                    TimelineBoundaryLabel(
                        date: end,
                        timeZoneIdentifier: row.occurrence.changesTimeZone
                            ? row.occurrence.endTimeZoneIdentifier
                            : row.occurrence.timeZoneIdentifier,
                        showsTimeZoneChange: row.occurrence.changesTimeZone,
                        needsReview: false
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

    var body: some View {
        VStack(spacing: 0) {
            TimelineTransitPseudoRulerRow(boundary: boundary)
            TimelineBoundaryLabel(
                date: date,
                timeZoneIdentifier: timeZoneIdentifier,
                showsTimeZoneChange: false,
                needsReview: false
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

    var body: some View {
        VStack(spacing: 0) {
            TimelineBoundaryLabel(
                date: date,
                timeZoneIdentifier: timeZoneIdentifier,
                showsTimeZoneChange: showsTimeZoneChange,
                needsReview: false
            )

            if let followingStart = boundary.followingTransitStart {
                TimelineTransitPseudoRulerRow(boundary: boundary)
                TimelineBoundaryLabel(
                    date: followingStart.date,
                    timeZoneIdentifier: followingStart.timeZoneIdentifier,
                    showsTimeZoneChange: false,
                    needsReview: false
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
                systemImage: boundary.systemImage
            )
        }
    }
}

private struct TimelineCompactMovementRulerRow: View {
    let occurrence: TimelineOccurrence
    let showsReviewBadge: Bool
    let reviewCandidateID: UUID?
    let onAcceptCandidateEntry: (UUID, UUID) -> Void
    let onDismissCandidate: (UUID) -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(
            spacing: TimelineRulerMetrics.cardSpacing
        ) {
            Color.clear
                .frame(width: TimelineRulerMetrics.trackWidth)

            TimelineCompactMovementRow(
                title: title,
                style: style,
                organizationName: occurrence.kind == .transit
                    ? occurrence.snapshot.transitSourceOrganizationName
                    : nil,
                serviceIdentifier: occurrence.kind == .transit
                    ? occurrence.snapshot.transitSourceServiceIdentifier
                    : nil,
                distanceMeters: occurrence.kind == .workout
                    ? occurrence.snapshot.workoutDistanceMeters
                    : occurrence.snapshot.transitDistanceMeters,
                startTime: occurrence.startTime,
                endTime: occurrence.endTime,
                people: occurrence.snapshot.people,
                showsReviewBadge: showsReviewBadge,
                reviewCandidateID: reviewCandidateID,
                onAcceptCandidate: {
                    onAcceptCandidateEntry(occurrence.entryID, $0)
                },
                onDismissCandidate: onDismissCandidate,
                onTap: onTap
            )
        }
    }

    private var title: String {
        occurrence.kind == .workout
            ? occurrence.snapshot.workoutActivityName
            : occurrence.transitType
    }

    private var style: TimelineCompactMovementStyle {
        if occurrence.kind == .workout {
            return .workout(
                systemImageName: occurrence.snapshot.workoutSystemImageName
            )
        }
        return .transit(
            TransitPresentationCatalog.presentation(for: occurrence.transitType)
        )
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
                    needsReview: showsBoundaryReviewBadges
                        && row.occurrence.reviewsTime
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
                    needsReview: showsBoundaryReviewBadges
                        && row.endBoundaryNeedsReview
                )
            }
        }
    }

    private var showsBoundaryReviewBadges: Bool {
        row.occurrence.kind != .placeVisit
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
    let transitGap: TimelineTransitGap?
    let separatesDistinctContiguousBoundary: Bool
    let onAddTransit: (TimelineTransitGapID) -> Void

    var body: some View {
        HStack(spacing: TimelineRulerMetrics.cardSpacing) {
            Color.clear.frame(width: TimelineRulerMetrics.trackWidth)

            if let transitGap {
                Button {
                    onAddTransit(transitGap.id)
                } label: {
                    Text(
                        "Add transit",
                        comment: "Creates a transit entry in a timeline gap"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text(
                        "Add transit from \(transitGap.originName) to \(transitGap.destinationName)"
                    )
                )
            }

            Spacer(minLength: 0)
        }
        .frame(height: height)
    }

    private var height: CGFloat {
        switch relationship {
        case .first: 0
        case .contiguous:
            separatesDistinctContiguousBoundary
                ? TimelineRulerMetrics.distinctContiguousBoundaryGap
                : 0
        case .overlap: 16
        case .gap(let duration):
            TimelineRulerMetrics.separateEntryGap(duration: duration)
                + (transitGap == nil
                    ? 0
                    : TimelineRulerMetrics.addTransitGapExpansion)
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
