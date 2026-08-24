import CoreMotion
import Foundation
import Testing

@testable import Journal

@Suite("Motion transit segmentation")
struct AutomationMotionTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Supported medium-confidence activities map to transit kinds")
    func categoryMapping() {
        #expect(MotionActivitySegmenter.kind(for: sample(.walking)) == .walk)
        #expect(MotionActivitySegmenter.kind(for: sample(.cycling)) == .bicycle)
        #expect(
            MotionActivitySegmenter.kind(for: sample(.automotive))
                == .automotive
        )
        #expect(MotionActivitySegmenter.kind(for: sample(.running)) == nil)
        #expect(MotionActivitySegmenter.kind(for: sample(.stationary)) == nil)
        #expect(MotionActivitySegmenter.kind(for: sample(.unknown)) == nil)
        #expect(MotionActivitySegmenter.kind(
            for: sample(.walking, confidence: .low)
        ) == nil)
    }

    @Test("Equal activities merge across a short gap")
    func merging() throws {
        let samples = [
            sample(.walking, offset: 0),
            sample(.stationary, offset: 4 * 60),
            sample(.walking, offset: 5 * 60),
            sample(.stationary, offset: 9 * 60),
        ]
        let segment = try #require(
            MotionActivitySegmenter.segments(from: samples).first
        )

        #expect(segment.kind == .walk)
        #expect(segment.startTime == start)
        #expect(segment.endTime == start.addingTimeInterval(9 * 60))
    }

    @Test("Short and unfinished activities do not produce candidates")
    func completionAndDuration() {
        #expect(MotionActivitySegmenter.segments(from: [
            sample(.cycling, offset: 0),
            sample(.stationary, offset: 2 * 60),
        ]).isEmpty)
        #expect(MotionActivitySegmenter.segments(from: [
            sample(.automotive, offset: 0),
        ]).isEmpty)
    }

    private enum Category: Equatable {
        case walking
        case running
        case cycling
        case automotive
        case stationary
        case unknown
    }

    private func sample(
        _ category: Category,
        offset: TimeInterval = 0,
        confidence: CMMotionActivityConfidence = .medium
    ) -> MotionActivitySample {
        MotionActivitySample(
            startTime: start.addingTimeInterval(offset),
            confidenceRawValue: confidence.rawValue,
            isWalking: category == .walking,
            isRunning: category == .running,
            isCycling: category == .cycling,
            isAutomotive: category == .automotive,
            isStationary: category == .stationary,
            isUnknown: category == .unknown
        )
    }
}
