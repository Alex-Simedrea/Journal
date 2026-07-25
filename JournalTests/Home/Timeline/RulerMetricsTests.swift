import CoreGraphics
import Testing
@testable import Journal

struct TimelineRulerMetricsTests {
    @Test func measuredGeometryMatchesReferenceStates() {
        #expect(TimelineRulerMetrics.trackWidth == 32)
        #expect(TimelineRulerMetrics.cardSpacing == 9)
        #expect(TimelineRulerMetrics.timestampSpacing == 6)
        #expect(TimelineRulerMetrics.wakeUpTimestampWidth == 38)
        #expect(TimelineRulerMetrics.wakeUpContentSpacing == 6)
        #expect(TimelineRulerMetrics.compactEntryHeight == 28)
        #expect(TimelineRulerMetrics.compactEntryBadgeSize == 26)
        #expect(TimelineRulerMetrics.compactEntryIconSize == 13)
        #expect(TimelineRulerMetrics.compactEntryContentSpacing == 8)
        #expect(TimelineRulerMetrics.tickPitch == 8)
        #expect(TimelineRulerMetrics.orphanBoundaryActiveTickCount == 5)
        #expect(TimelineRulerMetrics.wakeUpActiveRangeRadius == 4)
        #expect(TimelineRulerMetrics.endCapHeight == 16)
        #expect(TimelineRulerMetrics.firstTickOffset == 0.5)
        #expect(TimelineRulerMetrics.lineWidth == 1)
        #expect(TimelineRulerMetrics.activeRangeExpansion == 14)
        #expect(TimelineRulerMetrics.minimumSeparateEntryGap == 8)
        #expect(
            TimelineRulerMetrics.style(distanceFromActiveRange: 0)
                == TimelineRulerTickStyle(
                    level: .active,
                    length: 32,
                    opacity: 0.60
                )
        )
        #expect(
            TimelineRulerMetrics.style(distanceFromActiveRange: 8)
                == TimelineRulerTickStyle(
                    level: .shoulder,
                    length: 24,
                    opacity: 0.38
                )
        )
        #expect(
            TimelineRulerMetrics.style(distanceFromActiveRange: 16)
                == TimelineRulerTickStyle(
                    level: .middle,
                    length: 18,
                    opacity: 0.23
                )
        )
        #expect(
            TimelineRulerMetrics.style(distanceFromActiveRange: 17)
                == TimelineRulerTickStyle(
                    level: .quiet,
                    length: 16,
                    opacity: 0.23
                )
        )
    }

    @Test func orphanPseudoPlaceEmphasisAlwaysContainsFiveTicks() {
        let combinedBounds = CGRect(x: 0, y: 100, width: 200, height: 56)
        let shiftedBounds = CGRect(x: 0, y: 108, width: 200, height: 56)
        let standaloneBounds = CGRect(x: 0, y: 100, width: 200, height: 28)

        let combinedRange = TimelineRulerMetrics.boundaryConnectionRange(
            in: combinedBounds
        )
        let shiftedRange = TimelineRulerMetrics.boundaryConnectionRange(
            in: shiftedBounds
        )

        #expect(combinedRange == 112.5...144.5)
        #expect(shiftedRange == 120.5...152.5)
        #expect(activeTickCount(in: combinedRange) == 5)
        #expect(activeTickCount(in: shiftedRange) == 5)
        #expect(
            TimelineRulerMetrics.previousBoundaryConnectionRange(
                in: standaloneBounds
            ) == 86...114
        )
    }

    @Test func sharedPlaceGeometryIsBalancedAndFullyAccentuated() {
        let bounds = CGRect(x: 0, y: 100, width: 200, height: 84)

        #expect(
            TimelineRulerMetrics.sharedBoundaryConnectionRange(
                in: bounds
            ) == 110...174
        )
    }

    @Test func separateEntryGapsStayOnTheRulerCadence() {
        #expect(TimelineRulerMetrics.separateEntryGap(duration: 0) == 8)
        #expect(TimelineRulerMetrics.separateEntryGap(duration: 30 * 60) == 8)
        #expect(TimelineRulerMetrics.separateEntryGap(duration: 60 * 60) == 16)
        #expect(TimelineRulerMetrics.separateEntryGap(duration: 24 * 60 * 60) == 112)
    }

    @Test func measuredLengthRatiosRemainStable() {
        let active = TimelineRulerMetrics.style(distanceFromActiveRange: 0)
        let shoulder = TimelineRulerMetrics.style(distanceFromActiveRange: 1)
        let middle = TimelineRulerMetrics.style(distanceFromActiveRange: 9)
        let quiet = TimelineRulerMetrics.style(distanceFromActiveRange: 17)

        #expect(abs(shoulder.length / active.length - 0.75) < 0.001)
        #expect(abs(middle.length / active.length - 0.5625) < 0.001)
        #expect(abs(quiet.length / active.length - 0.5) < 0.001)
    }

    @Test func measuredLightModeColorsRemainExact() {
        #expect(
            TimelineRulerPalette.lightLine(level: .active)
                == RGBColor(red: 96, green: 96, blue: 103)
        )
        #expect(
            TimelineRulerPalette.lightLine(level: .shoulder)
                == RGBColor(red: 151, green: 151, blue: 157)
        )
        #expect(
            TimelineRulerPalette.lightLine(level: .middle)
                == RGBColor(red: 187, green: 187, blue: 193)
        )
        #expect(
            TimelineRulerPalette.lightLine(level: .quiet)
                == RGBColor(red: 187, green: 187, blue: 193)
        )
        #expect(
            TimelineRulerPalette.lightTimestamp
                == RGBColor(red: 121, green: 121, blue: 124)
        )
    }

    private func activeTickCount(
        in range: ClosedRange<CGFloat>
    ) -> Int {
        var count = 0
        var y = TimelineRulerMetrics.firstTickOffset
        while y <= range.upperBound {
            if range.contains(y) {
                count += 1
            }
            y += TimelineRulerMetrics.tickPitch
        }
        return count
    }
}
