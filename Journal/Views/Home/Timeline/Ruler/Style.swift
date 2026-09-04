import SwiftUI

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
    static let boundaryLabelHeight: CGFloat = TimelineGapLayout.boundaryLabelHeight
    static let wakeUpTimestampWidth: CGFloat = 38
    static let wakeUpContentSpacing: CGFloat = 6
    static let compactEntryHeight: CGFloat = 38
    static let pseudoPlaceHeight: CGFloat = TimelineGapLayout.pseudoPlaceHeight
    static let compactMovementActiveTickCount = 5
    static let compactEntryBadgeSize: CGFloat = 26
    static let compactEntryIconSize: CGFloat = 13
    static let compactEntryContentSpacing: CGFloat = 8
    static let tickPitch: CGFloat = TimelineGapLayout.tickPitch
    static let wakeUpActiveRangeRadius: CGFloat = tickPitch / 2
    static let endCapHeight: CGFloat = tickPitch * 2
    static let firstTickOffset: CGFloat = 0.5
    static let lineWidth: CGFloat = 1
    static let activeRangeExpansion: CGFloat = 14
    static let minimumSeparateEntryGap: CGFloat = TimelineGapLayout.minimumSeparateEntryGap
    static let distinctContiguousBoundaryGap: CGFloat = tickPitch
    static let addTransitGapExpansion: CGFloat = tickPitch
    static let maximumSeparateEntryGap: CGFloat = TimelineGapLayout.maximumSeparateEntryGap

    // The reference has five full-width ticks centered on each movement.
    // Snap to the track cadence so an offset row cannot lose an edge tick.
    static func compactMovementRange(in bounds: CGRect) -> ClosedRange<CGFloat> {
        let centerIndex = ((bounds.midY - firstTickOffset) / tickPitch).rounded()
        let center = firstTickOffset + centerIndex * tickPitch
        let radius = CGFloat(compactMovementActiveTickCount - 1) * tickPitch / 2
        return (center - radius)...(center + radius)
    }

    static func placeVisitRange(
        in bounds: CGRect,
        previousMovement: CGRect? = nil,
        nextMovement: CGRect? = nil
    ) -> ClosedRange<CGFloat> {
        var lower = bounds.minY - activeRangeExpansion
        var upper = bounds.maxY + activeRangeExpansion
        // Three tick pitches between active endpoints leave exactly two
        // shoulder ticks around a shared timestamp, regardless of row offset.
        if let previousMovement,
           abs(bounds.minY - previousMovement.maxY - boundaryLabelHeight) < 0.5 {
            lower = compactMovementRange(in: previousMovement).upperBound
                + tickPitch * 3
        }
        if let nextMovement,
           abs(nextMovement.minY - bounds.maxY - boundaryLabelHeight) < 0.5 {
            upper = compactMovementRange(in: nextMovement).lowerBound
                - tickPitch * 3
        }
        return lower...upper
    }

    static func separateEntryGap(duration: TimeInterval) -> CGFloat {
        TimelineGapLayout.separateEntryGap(duration: duration)
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

    static func lightLine(level: TimelineRulerTickLevel) -> RGBColor {
        switch level {
        case .active: RGBColor(red: 96, green: 96, blue: 103)
        case .shoulder: RGBColor(red: 151, green: 151, blue: 157)
        case .middle, .quiet:
            RGBColor(red: 187, green: 187, blue: 193)
        }
    }

    static func timestamp(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
            : lightTimestamp.color
    }

    static let lightTimestamp = RGBColor(
        red: 121,
        green: 121,
        blue: 124
    )
}
