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
        #expect(TimelineRulerMetrics.compactEntryHeight == 38)
        #expect(TimelineRulerMetrics.compactEntryBadgeSize == 26)
        #expect(TimelineRulerMetrics.compactEntryIconSize == 13)
        #expect(TimelineRulerMetrics.compactEntryContentSpacing == 8)
        #expect(TimelineRulerMetrics.tickPitch == 8)
        #expect(TimelineRulerMetrics.pseudoPlaceHeight == 18)
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

    @Test func movementEmphasisTapersBeforeReachingSharedPlace() {
        // Reference: movement, timestamp, shared place, timestamp, movement.
        let movement = CGRect(x: 0, y: 0, width: 200, height: 38)
        let sharedPlace = CGRect(x: 0, y: movement.maxY + 28, width: 200, height: 18)
        let nextMovementY = sharedPlace.maxY + 28
        #expect(nextMovementY == 112)
        for offset in stride(from: CGFloat(0), through: 8, by: 0.5) {
            let range = TimelineRulerMetrics.compactMovementRange(
                in: movement.offsetBy(dx: 0, dy: offset)
            )
            #expect(activeTickCount(in: range) == 5)
            #expect(range.upperBound - range.lowerBound == 32)
            #expect(TimelineRulerMetrics.style(distanceFromActiveRange: 8).level == .shoulder)
            #expect(TimelineRulerMetrics.style(distanceFromActiveRange: 16).level == .middle)
            #expect(TimelineRulerMetrics.style(distanceFromActiveRange: 24).level == .quiet)
        }
        #expect(TimelineRulerMetrics.style(distanceFromActiveRange: 6.5).level == .shoulder)
        #expect(TimelineRulerMetrics.style(distanceFromActiveRange: 14.5).level == .middle)
        #expect(TimelineRulerMetrics.style(distanceFromActiveRange: 22.5).level == .quiet)
        #expect(TimelineRulerMetrics.style(distanceFromActiveRange: sharedPlace.midY - movement.maxY).level == .quiet)
    }

    @Test func placeVisitHandoffsAlwaysLeaveTwoShoulderTicks() {
        for offset in stride(from: CGFloat(0), through: 8, by: 0.5) {
            for height: CGFloat in [52, 72, 110] {
                let before = CGRect(x: 0, y: offset, width: 200, height: height)
                let movement = CGRect(
                    x: 0, y: before.maxY + 28, width: 200, height: 38
                )
                let after = CGRect(
                    x: 0, y: movement.maxY + 28, width: 200, height: height
                )
                let movementRange = TimelineRulerMetrics.compactMovementRange(in: movement)
                let beforeRange = TimelineRulerMetrics.placeVisitRange(
                    in: before, nextMovement: movement
                )
                let afterRange = TimelineRulerMetrics.placeVisitRange(
                    in: after, previousMovement: movement
                )
                for (start, end) in [
                    (beforeRange.upperBound, movementRange.lowerBound),
                    (movementRange.upperBound, afterRange.lowerBound),
                ] {
                    #expect(end - start == 24)
                    let interiorTicks = stride(from: start + 8, to: end, by: 8)
                    #expect(Array(interiorTicks).count == 2)
                    for tick in interiorTicks {
                        let distance = min(tick - start, end - tick)
                        #expect(TimelineRulerMetrics.style(distanceFromActiveRange: distance).level == .shoulder)
                    }
                }
            }
        }
    }

    @Test func separatePlaceVisitsKeepTheirNormalTaper() {
        let visit = CGRect(x: 0, y: 100, width: 200, height: 72)
        let movement = CGRect(x: 0, y: visit.maxY + 28 + 8, width: 200, height: 38)
        #expect(TimelineRulerMetrics.placeVisitRange(in: visit) == 86...186)
        #expect(
            TimelineRulerMetrics.placeVisitRange(in: visit, nextMovement: movement)
                == 86...186
        )
    }

    @Test func separateEntryGapsStayOnTheRulerCadence() {
        #expect(TimelineRulerMetrics.separateEntryGap(duration: 0) == 8)
        #expect(TimelineRulerMetrics.separateEntryGap(duration: 30 * 60) == 8)
        #expect(TimelineRulerMetrics.separateEntryGap(duration: 60 * 60) == 16)
        #expect(TimelineRulerMetrics.separateEntryGap(duration: 24 * 60 * 60) == 112)
    }

    @Test func sharedMovementBoundariesSeparateOnlyWhenTimeSpacingIsLarger() {
        #expect(TimelineGapLayout.sharedMovementBoundaryHeight == 74)
        #expect(!TimelineGapLayout.separatesSharedMovementBoundary(duration: 288 * 60))
        #expect(TimelineGapLayout.separatesSharedMovementBoundary(duration: 288 * 60 + 1))
        #expect(TimelineGapLayout.separateEntryGap(duration: 392 * 60) == 104)
        #expect(TimelineGapLayout.separatesSharedMovementBoundary(duration: 392 * 60))
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
