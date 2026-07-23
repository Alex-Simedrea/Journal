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
    static let wakeUpTimestampWidth: CGFloat = 38
    static let wakeUpContentSpacing: CGFloat = 6
    static let tickPitch: CGFloat = 8
    static let wakeUpActiveRangeRadius: CGFloat = tickPitch / 2
    static let endCapHeight: CGFloat = tickPitch * 2
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
