import Foundation

nonisolated enum TimelineGapLayout {
    static let boundaryLabelHeight: CGFloat = 28
    static let pseudoPlaceHeight: CGFloat = 18
    static let tickPitch: CGFloat = 8
    static let minimumSeparateEntryGap: CGFloat = 8
    static let maximumSeparateEntryGap: CGFloat = 112

    static var sharedMovementBoundaryHeight: CGFloat {
        boundaryLabelHeight * 2 + pseudoPlaceHeight
    }

    static func separateEntryGap(duration: TimeInterval) -> CGFloat {
        let scaled = max(minimumSeparateEntryGap, max(duration / 60, 0) / 4)
        let quantized = ceil(scaled / tickPitch) * tickPitch
        return min(maximumSeparateEntryGap, quantized)
    }

    static func separatesSharedMovementBoundary(duration: TimeInterval) -> Bool {
        separateEntryGap(duration: duration) > sharedMovementBoundaryHeight
    }
}
