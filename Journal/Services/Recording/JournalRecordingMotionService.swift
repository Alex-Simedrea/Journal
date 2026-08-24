import CoreMotion
import Foundation

@MainActor
final class JournalRecordingMotionService {
    private let manager = CMMotionActivityManager()

    func observations(
        from start: Date,
        to end: Date
    ) async throws -> [RecordedMotionObservation] {
        guard CMMotionActivityManager.isActivityAvailable(), end > start else {
            return []
        }
        let activities = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[CMMotionActivity], Error>) in
            manager.queryActivityStarting(from: start, to: end, to: .main) {
                activities, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: activities ?? [])
                }
            }
        }
        let ordered = activities.sorted { $0.startDate < $1.startDate }
        return ordered.enumerated().map { index, activity in
            let observationEnd = index + 1 < ordered.count
                ? min(end, ordered[index + 1].startDate)
                : end
            return RecordedMotionObservation(
                startTime: max(start, activity.startDate),
                endTime: observationEnd,
                kind: Self.kind(activity),
                confidenceRawValue: activity.confidence.rawValue
            )
        }.filter { $0.endTime > $0.startTime }
    }

    private static func kind(_ activity: CMMotionActivity) -> RecordedMotionKind {
        if activity.automotive { return .automotive }
        if activity.cycling { return .cycling }
        if activity.running { return .running }
        if activity.walking { return .walking }
        if activity.stationary { return .stationary }
        return .unknown
    }
}
