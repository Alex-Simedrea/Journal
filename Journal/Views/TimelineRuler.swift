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
            ForEach(rows) { row in
                TimelineRulerRow(
                    row: row,
                    onSelect: onSelect
                )
            }
        }
        .overlayPreferenceValue(TimelineCardBoundsKey.self) { anchors in
            TimelineRulerOverlay(cardBounds: anchors)
        }
        .padding(.horizontal)
    }
}

private struct TimelineCardBoundsKey: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []

    static func reduce(
        value: inout [Anchor<CGRect>],
        nextValue: () -> [Anchor<CGRect>]
    ) {
        value.append(contentsOf: nextValue())
    }
}

private struct TimelineRulerOverlay: View {
    let cardBounds: [Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            TimelineRulerTrack(
                activeRanges: cardBounds.map { anchor in
                    let bounds = proxy[anchor]
                    return (
                        bounds.minY - TimelineRulerMetrics.activeRangeExpansion
                    )...(
                        bounds.maxY + TimelineRulerMetrics.activeRangeExpansion
                    )
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
            TimelineRulerGap(relationship: row.relationshipToPrevious)

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
                    transform: { [$0] }
                )
            }

            if let end = row.occurrence.visibleEndTime {
                TimelineBoundaryLabel(
                    date: end,
                    timeZoneIdentifier: row.occurrence.changesTimeZone
                        ? row.occurrence.endTimeZoneIdentifier
                        : row.occurrence.timeZoneIdentifier,
                    showsTimeZoneChange: row.occurrence.changesTimeZone,
                    needsReview: row.occurrence.reviewsTime
                )
            }
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

            Text(date, format: .dateTime.hour().minute())
                .environment(
                    \.timeZone,
                    TimeZone(identifier: timeZoneIdentifier) ?? .current
                )
                .monospacedDigit()

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
                TimelineReviewBadge()
            }

            Spacer()
        }
        .font(.caption)
        .foregroundStyle(TimelineRulerPalette.timestamp(colorScheme: colorScheme))
        .frame(height: 28)
        .accessibilityElement(children: .combine)
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

enum TimelineRulerTickLevel: Equatable {
    case active
    case shoulder
    case middle
    case quiet
}

struct TimelineRulerTickStyle: Equatable {
    let level: TimelineRulerTickLevel
    let length: CGFloat
    let opacity: Double
}

enum TimelineRulerMetrics {
    static let trackWidth: CGFloat = 32
    static let cardSpacing: CGFloat = 9
    static let timestampSpacing: CGFloat = 6
    static let tickPitch: CGFloat = 8
    static let firstTickOffset: CGFloat = 0.5
    static let lineWidth: CGFloat = 1
    static let activeRangeExpansion: CGFloat = 14
    static let minimumSeparateEntryGap: CGFloat = 8
    static let maximumSeparateEntryGap: CGFloat = 112

    static func separateEntryGap(duration: TimeInterval) -> CGFloat {
        let scaled = max(
            minimumSeparateEntryGap,
            max(duration / 60, 0) / 4
        )
        let quantized = ceil(scaled / tickPitch) * tickPitch
        return min(maximumSeparateEntryGap, quantized)
    }

    static func style(
        distanceFromActiveRange distance: CGFloat
    ) -> TimelineRulerTickStyle {
        if distance <= 0 {
            return TimelineRulerTickStyle(
                level: .active,
                length: 32,
                opacity: 0.60
            )
        }
        if distance <= tickPitch {
            return TimelineRulerTickStyle(
                level: .shoulder,
                length: 24,
                opacity: 0.38
            )
        }
        if distance <= tickPitch * 2 {
            return TimelineRulerTickStyle(
                level: .middle,
                length: 18,
                opacity: 0.23
            )
        }
        return TimelineRulerTickStyle(
            level: .quiet,
            length: 16,
            opacity: 0.23
        )
    }
}

struct TimelineRulerRGB: Equatable {
    let red: Int
    let green: Int
    let blue: Int

    var color: Color {
        Color(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
    }
}

enum TimelineRulerPalette {
    static func line(
        level: TimelineRulerTickLevel,
        colorScheme: ColorScheme
    ) -> Color {
        if colorScheme == .dark {
            return switch level {
            case .active: Color(white: 0.60)
            case .shoulder: Color(white: 0.38)
            case .middle, .quiet: Color(white: 0.23)
            }
        }
        return lightLine(level: level).color
    }

    static func lightLine(level: TimelineRulerTickLevel) -> TimelineRulerRGB {
        switch level {
        case .active: TimelineRulerRGB(red: 96, green: 96, blue: 103)
        case .shoulder: TimelineRulerRGB(red: 151, green: 151, blue: 157)
        case .middle, .quiet:
            TimelineRulerRGB(red: 187, green: 187, blue: 193)
        }
    }

    static func timestamp(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
            : lightTimestamp.color
    }

    static let lightTimestamp = TimelineRulerRGB(
        red: 121,
        green: 121,
        blue: 124
    )
}

struct TimelineUnplacedSection: View {
    let occurrences: [TimelineOccurrence]
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Unplaced Entries", systemImage: "exclamationmark.clock")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(occurrences) { occurrence in
                TimelineEntryCard(
                    occurrence: occurrence,
                    onTap: { onSelect(occurrence.entryID) }
                )
            }
        }
        .padding(.horizontal)
        .padding(.top, 28)
    }
}

struct TimelineReviewBadge: View {
    var body: some View {
        Image(systemName: "exclamationmark")
            .resizable()
            .scaledToFit()
            .fontWeight(.black)
            .foregroundStyle(.white)
            .frame(width: 3, height: 9)
            .frame(width: 17, height: 17)
            .background(.orange, in: .circle)
            .accessibilityLabel("Needs review")
    }
}
