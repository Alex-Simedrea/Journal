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
    let onAddPlaceVisit: (TimelinePlaceVisitGapID) -> Void
    let onResolveBoundary: (TimelineBoundaryConflictID) -> Void
    let expandsMovementCards: Bool
    let dimmedEntryIDs: Set<UUID>
    let showsTransitGapActions: Bool
    let linkHighlightedEntryIDs: Set<UUID>
    let linkedEndBoundaryEntryIDs: Set<UUID>
    let showsEndCaps: Bool
    let endCapHeight: CGFloat
    let fixedSeparatedEntryGap: CGFloat?

    init(
        rows: [TimelineRow],
        pendingAutomationCandidateIDsByEntryID: [UUID: UUID],
        onSelect: @escaping (UUID) -> Void,
        onAcceptCandidateEntry: @escaping (UUID, UUID) -> Void,
        onDismissCandidate: @escaping (UUID) -> Void,
        onAddTransit: @escaping (TimelineTransitGapID) -> Void,
        onAddPlaceVisit: @escaping (TimelinePlaceVisitGapID) -> Void = { _ in },
        onResolveBoundary: @escaping (TimelineBoundaryConflictID) -> Void = { _ in },
        expandsMovementCards: Bool = false,
        dimmedEntryIDs: Set<UUID> = [],
        showsTransitGapActions: Bool = true,
        linkHighlightedEntryIDs: Set<UUID> = [],
        linkedEndBoundaryEntryIDs: Set<UUID> = [],
        showsEndCaps: Bool = true,
        endCapHeight: CGFloat = TimelineRulerMetrics.endCapHeight,
        fixedSeparatedEntryGap: CGFloat? = nil
    ) {
        self.rows = rows
        self.pendingAutomationCandidateIDsByEntryID =
            pendingAutomationCandidateIDsByEntryID
        self.onSelect = onSelect
        self.onAcceptCandidateEntry = onAcceptCandidateEntry
        self.onDismissCandidate = onDismissCandidate
        self.onAddTransit = onAddTransit
        self.onAddPlaceVisit = onAddPlaceVisit
        self.onResolveBoundary = onResolveBoundary
        self.expandsMovementCards = expandsMovementCards
        self.dimmedEntryIDs = dimmedEntryIDs
        self.showsTransitGapActions = showsTransitGapActions
        self.linkHighlightedEntryIDs = linkHighlightedEntryIDs
        self.linkedEndBoundaryEntryIDs = linkedEndBoundaryEntryIDs
        self.showsEndCaps = showsEndCaps
        self.endCapHeight = endCapHeight
        self.fixedSeparatedEntryGap = fixedSeparatedEntryGap
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsEndCaps {
                TimelineRulerEndCap(height: endCapHeight)
            }

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
                    onAddTransit: onAddTransit,
                    onAddPlaceVisit: onAddPlaceVisit,
                    onResolveBoundary: onResolveBoundary,
                    expandsMovementCards: expandsMovementCards,
                    dimmedEntryIDs: dimmedEntryIDs,
                    showsTransitGapActions: showsTransitGapActions,
                    linkHighlightedEntryIDs: linkHighlightedEntryIDs,
                    linkedEndBoundaryEntryIDs: linkedEndBoundaryEntryIDs,
                    fixedSeparatedEntryGap: fixedSeparatedEntryGap
                )
            }

            if showsEndCaps {
                TimelineRulerEndCap(height: endCapHeight)
            }
        }
        .overlayPreferenceValue(TimelineCardBoundsKey.self) { anchors in
            TimelineRulerOverlay(cardBounds: anchors)
        }
        .padding(.horizontal)
    }
}

private struct TimelineRulerEndCap: View {
    let height: CGFloat

    var body: some View {
        Color.clear.frame(height: height)
    }
}

private struct TimelineRulerActiveBounds {
    let anchor: Anchor<CGRect>
    let rangeStyle: TimelineRulerActiveRangeStyle
}

private enum TimelineRulerActiveRangeStyle {
    case interval(expansion: CGFloat)
    case placeVisit
    case moment(radius: CGFloat)
    case compactMovement
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
            let resolvedBounds = cardBounds.map {
                (bounds: proxy[$0.anchor], style: $0.rangeStyle)
            }
            TimelineRulerTrack(
                activeRanges: resolvedBounds.enumerated().map { index, item in
                    let bounds = item.bounds
                    switch item.style {
                    case .interval(let expansion):
                        return (bounds.minY - expansion)...(bounds.maxY + expansion)
                    case .placeVisit:
                        var previousMovement: CGRect?
                        var nextMovement: CGRect?
                        if index > 0,
                           case .compactMovement = resolvedBounds[index - 1].style {
                            previousMovement = resolvedBounds[index - 1].bounds
                        }
                        if index + 1 < resolvedBounds.count,
                           case .compactMovement = resolvedBounds[index + 1].style {
                            nextMovement = resolvedBounds[index + 1].bounds
                        }
                        return TimelineRulerMetrics.placeVisitRange(
                            in: bounds,
                            previousMovement: previousMovement,
                            nextMovement: nextMovement
                        )
                    case .moment(let radius):
                        return (bounds.midY - radius)...(bounds.midY + radius)
                    case .compactMovement:
                        return TimelineRulerMetrics.compactMovementRange(in: bounds)
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
    let onAddPlaceVisit: (TimelinePlaceVisitGapID) -> Void
    let onResolveBoundary: (TimelineBoundaryConflictID) -> Void
    let expandsMovementCards: Bool
    let dimmedEntryIDs: Set<UUID>
    let showsTransitGapActions: Bool
    let linkHighlightedEntryIDs: Set<UUID>
    let linkedEndBoundaryEntryIDs: Set<UUID>
    let fixedSeparatedEntryGap: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            if !row.startBoundaryRenderedByPrevious {
                TimelineRulerGap(
                    relationship: row.relationshipToPrevious,
                    transitGap: showsTransitGapActions ? row.transitGap : nil,
                    boundaryConflict: showsTransitGapActions
                        ? row.boundaryConflict : nil,
                    separatesDistinctContiguousBoundary:
                        row.presentsDistinctContiguousTransitStart,
                    onAddTransit: onAddTransit,
                    onResolveBoundary: onResolveBoundary,
                    fixedSeparatedEntryGap: fixedSeparatedEntryGap
                )
            }

            switch row.occurrence.kind {
            case .wakeUp:
                TimelineWakeUpRulerContent(occurrence: row.occurrence)
            case .transit:
                if expandsMovementCards {
                    TimelineIntervalRulerContent(
                        row: row,
                        onSelect: onSelect,
                        isDimmed: dimmedEntryIDs.contains(row.occurrence.entryID),
                        isLinkHighlighted: linkHighlightedEntryIDs.contains(
                            row.occurrence.entryID
                        ),
                        showsLinkedEndBoundary: linkedEndBoundaryEntryIDs
                            .contains(row.occurrence.entryID)
                    )
                } else if let presentation = row.transitPresentation {
                    TimelineTransitRulerContent(
                        row: row,
                        presentation: presentation,
                        reviewCandidateID: reviewCandidateID,
                        onSelect: onSelect,
                        onAcceptCandidateEntry: onAcceptCandidateEntry,
                        onDismissCandidate: onDismissCandidate,
                        onAddPlaceVisit: showsTransitGapActions ? onAddPlaceVisit : nil
                    )
                }
            case .workout:
                if expandsMovementCards {
                    TimelineIntervalRulerContent(
                        row: row,
                        onSelect: onSelect,
                        isDimmed: dimmedEntryIDs.contains(row.occurrence.entryID),
                        isLinkHighlighted: linkHighlightedEntryIDs.contains(
                            row.occurrence.entryID
                        ),
                        showsLinkedEndBoundary: linkedEndBoundaryEntryIDs
                            .contains(row.occurrence.entryID)
                    )
                } else if let presentation = row.transitPresentation {
                    TimelineTransitRulerContent(
                        row: row,
                        presentation: presentation,
                        reviewCandidateID: nil,
                        onSelect: onSelect,
                        onAcceptCandidateEntry: onAcceptCandidateEntry,
                        onDismissCandidate: onDismissCandidate,
                        onAddPlaceVisit: showsTransitGapActions ? onAddPlaceVisit : nil
                    )
                } else {
                    TimelineIntervalRulerContent(
                        row: row,
                        onSelect: onSelect,
                        isDimmed: dimmedEntryIDs.contains(row.occurrence.entryID),
                        isLinkHighlighted: linkHighlightedEntryIDs.contains(
                            row.occurrence.entryID
                        ),
                        showsLinkedEndBoundary: linkedEndBoundaryEntryIDs
                            .contains(row.occurrence.entryID)
                    )
                }
            case .placeVisit:
                TimelineIntervalRulerContent(
                    row: row,
                    onSelect: onSelect,
                    isDimmed: dimmedEntryIDs.contains(row.occurrence.entryID),
                    isLinkHighlighted: linkHighlightedEntryIDs.contains(
                        row.occurrence.entryID
                    ),
                    showsLinkedEndBoundary: linkedEndBoundaryEntryIDs
                        .contains(row.occurrence.entryID)
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
    let onAddPlaceVisit: ((TimelinePlaceVisitGapID) -> Void)?

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
                        showsTimeZoneChange: row.occurrence.changesTimeZone,
                        onAddPlaceVisit: onAddPlaceVisit
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
    }
}

private struct TimelineTransitDestinationBoundaryBlock: View {
    let boundary: TimelineTransitBoundaryPresentation
    let date: Date
    let timeZoneIdentifier: String
    let showsTimeZoneChange: Bool
    let onAddPlaceVisit: ((TimelinePlaceVisitGapID) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            TimelineBoundaryLabel(
                date: date,
                timeZoneIdentifier: timeZoneIdentifier,
                showsTimeZoneChange: showsTimeZoneChange,
                needsReview: false
            )

            if let followingStart = boundary.followingTransitStart {
                TimelineTransitPseudoRulerRow(
                    boundary: boundary,
                    onAddPlaceVisit: onAddPlaceVisit
                )
                TimelineBoundaryLabel(
                    date: followingStart.date,
                    timeZoneIdentifier: followingStart.timeZoneIdentifier,
                    showsTimeZoneChange: false,
                    needsReview: false
                )
            } else {
                TimelineTransitPseudoRulerRow(
                    boundary: boundary,
                    onAddPlaceVisit: onAddPlaceVisit
                )
            }
        }
    }
}

private struct TimelineTransitPseudoRulerRow: View {
    let boundary: TimelineTransitBoundaryPresentation
    var onAddPlaceVisit: ((TimelinePlaceVisitGapID) -> Void)? = nil

    var body: some View {
        HStack(
            spacing: TimelineRulerMetrics.cardSpacing
        ) {
            Color.clear
                .frame(width: TimelineRulerMetrics.trackWidth)

            TimelineTransitPseudoPlaceRow(
                name: boundary.name,
                systemImage: boundary.systemImage,
                onAddPlaceVisit: addPlaceVisitAction
            )
        }
    }

    private var addPlaceVisitAction: (() -> Void)? {
        guard let gapID = boundary.placeVisitGapID, let onAddPlaceVisit else {
            return nil
        }
        return { onAddPlaceVisit(gapID) }
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
                activeEnergyKilocalories: occurrence.kind == .workout
                    ? occurrence.snapshot.workoutActiveEnergyKilocalories : nil,
                photoReferences: occurrence.snapshot.photoReferences,
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
        .anchorPreference(key: TimelineCardBoundsKey.self, value: .bounds) {
            [
                TimelineRulerActiveBounds(
                    anchor: $0,
                    rangeStyle: .compactMovement
                )
            ]
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
    let isDimmed: Bool
    let isLinkHighlighted: Bool
    let showsLinkedEndBoundary: Bool

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
                    onTap: { onSelect(row.occurrence.entryID) },
                    temporaryLinkHighlight: isLinkHighlighted
                )
                .disabled(isDimmed)
                .anchorPreference(
                    key: TimelineCardBoundsKey.self,
                    value: .bounds,
                    transform: {
                        [
                            TimelineRulerActiveBounds(
                                anchor: $0,
                                rangeStyle: row.occurrence.kind == .placeVisit
                                    ? .placeVisit : .interval(
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
                        && row.endBoundaryNeedsReview,
                    showsLinkIndicator: showsLinkedEndBoundary
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
    let boundaryConflict: TimelineBoundaryConflictID?
    let separatesDistinctContiguousBoundary: Bool
    let onAddTransit: (TimelineTransitGapID) -> Void
    let onResolveBoundary: (TimelineBoundaryConflictID) -> Void
    let fixedSeparatedEntryGap: CGFloat?

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

            if let boundaryConflict {
                Button("Resolve") {
                    onResolveBoundary(boundaryConflict)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.blue)
                .buttonStyle(.plain)
                .accessibilityLabel("Resolve mismatched locations")
            }

            Spacer(minLength: 0)
        }
        .frame(height: height)
    }

    private var height: CGFloat {
        switch relationship {
        case .first: 0
        case .contiguous:
            boundaryConflict != nil
                ? TimelineRulerMetrics.boundaryLabelHeight
                : separatesDistinctContiguousBoundary
                ? TimelineRulerMetrics.distinctContiguousBoundaryGap
                : 0
        case .overlap:
            fixedSeparatedEntryGap ?? 16
        case .gap(let duration):
            (fixedSeparatedEntryGap
                ?? TimelineRulerMetrics.separateEntryGap(duration: duration))
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
    var showsLinkIndicator = false

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

            if showsLinkIndicator {
                HStack(spacing: 3) {
                    Image(systemName: "link")
                    Text("Linked")
                }
                .foregroundStyle(.blue)
                .bold()
            }

            Spacer()
        }
        .font(.caption)
        .foregroundStyle(TimelineRulerPalette.timestamp(colorScheme: colorScheme))
        .frame(height: TimelineRulerMetrics.boundaryLabelHeight)
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
