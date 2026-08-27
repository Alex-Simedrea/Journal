import Foundation
import SwiftData
import Testing

@testable import Journal

@Suite("Manual journal recording")
struct JournalRecordingClassifierTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Stationary GPS drift is classified as a place visit")
    func stationaryDrift() throws {
        let points = [
            point(north: -9, east: 4, minute: 0, accuracy: 12),
            point(north: 6, east: -7, minute: 2, accuracy: 9),
            point(north: 11, east: 8, minute: 8, accuracy: 14),
            point(north: -4, east: -5, minute: 15, accuracy: 10),
            point(north: 3, east: 2, minute: 30, accuracy: 8),
        ]

        let result = try #require(
            JournalRecordingClassifier.classify(points: points, motion: [])
        )
        guard case .visit(_, let radius) = result else {
            Issue.record("Expected a visit")
            return
        }
        #expect(radius < 30)
    }

    @Test("A poor-accuracy outlier does not turn a visit into transit")
    func ignoresPoorAccuracy() throws {
        let points = [
            point(north: 0, east: 0, minute: 0, accuracy: 8),
            point(north: 500, east: 500, minute: 1, accuracy: 400),
            point(north: 4, east: -3, minute: 10, accuracy: 10),
        ]
        let result = try #require(
            JournalRecordingClassifier.classify(points: points, motion: [])
        )
        guard case .visit = result else {
            Issue.record("Expected a visit")
            return
        }
    }

    @Test("A route uses endpoint clusters and preserves automotive motion")
    func transitEndpointClusters() throws {
        let points = [
            point(north: 70, east: 70, minute: 0, accuracy: 100),
            point(north: 2, east: -3, minute: 1, accuracy: 7),
            point(north: -2, east: 2, minute: 2, accuracy: 8),
            point(north: 300, east: 10, minute: 5, accuracy: 8),
            point(north: 700, east: 20, minute: 9, accuracy: 8),
            point(north: 1_000, east: -2, minute: 12, accuracy: 7),
            point(north: 1_004, east: 3, minute: 13, accuracy: 8),
        ]
        let motion = [
            RecordedMotionObservation(
                startTime: start,
                endTime: start.addingTimeInterval(2 * 60),
                kind: .walking,
                confidenceRawValue: 1
            ),
            RecordedMotionObservation(
                startTime: start.addingTimeInterval(2 * 60),
                endTime: start.addingTimeInterval(12 * 60),
                kind: .automotive,
                confidenceRawValue: 2
            ),
        ]
        let result = try #require(
            JournalRecordingClassifier.classify(points: points, motion: motion)
        )
        guard case .transit(
            let origin,
            let destination,
            let route,
            let distance,
            let mode
        ) = result else {
            Issue.record("Expected transit")
            return
        }
        #expect(abs(origin.latitude - baseLatitude) < 0.0003)
        #expect(abs(destination.latitude - latitude(north: 1_000)) < 0.0002)
        #expect(route.count >= 2)
        #expect(distance > 800)
        #expect(mode == .automotive)
    }

    @Test("A closed rectangular walk is transit")
    func closedRectangularWalk() throws {
        let points = [
            point(north: 0, east: 0, minute: 0, speed: 1.4),
            point(north: 0, east: 75, minute: 1, speed: 1.4),
            point(north: 75, east: 75, minute: 2, speed: 1.4),
            point(north: 75, east: 0, minute: 3, speed: 1.4),
            point(north: 0, east: 0, minute: 4, speed: 1.4),
        ]
        let motion = [
            RecordedMotionObservation(
                startTime: start,
                endTime: start.addingTimeInterval(4 * 60),
                kind: .walking,
                confidenceRawValue: 2
            )
        ]

        let result = try #require(
            JournalRecordingClassifier.classify(
                points: points,
                motion: motion
            )
        )

        guard case .transit(_, _, _, let distance, let mode) = result else {
            Issue.record("Expected the closed walk to be transit")
            return
        }
        #expect(distance > 250)
        #expect(mode == .walking)
    }

    @Test("An out-and-back route is transit without endpoint displacement")
    func outAndBackRoute() throws {
        let points = [
            point(north: 0, east: 0, minute: 0, speed: 1.5),
            point(north: 1_500, east: 0, minute: 15, speed: 1.5),
            point(north: 3_000, east: 0, minute: 30, speed: 1.5),
            point(north: 1_500, east: 0, minute: 45, speed: 1.5),
            point(north: 0, east: 0, minute: 60, speed: 1.5),
        ]

        let result = try #require(
            JournalRecordingClassifier.classify(points: points, motion: [])
        )

        guard case .transit(_, _, _, let distance, let mode) = result else {
            Issue.record("Expected the out-and-back walk to be transit")
            return
        }
        #expect(distance > 5_500)
        #expect(mode == .walking)
    }

    @Test("Sustained motion supports a sparse short route")
    func sparseRouteWithMotion() throws {
        let points = [
            point(north: 0, east: 0, minute: 0),
            point(north: 50, east: 0, minute: 3),
        ]
        let motion = [
            RecordedMotionObservation(
                startTime: start,
                endTime: start.addingTimeInterval(3 * 60),
                kind: .walking,
                confidenceRawValue: 2
            )
        ]

        let result = try #require(
            JournalRecordingClassifier.classify(
                points: points,
                motion: motion
            )
        )

        guard case .transit(_, _, _, _, let mode) = result else {
            Issue.record("Expected sparse sustained movement to be transit")
            return
        }
        #expect(mode == .walking)
    }

    @Test("High GPS speed alone is not classified as automotive")
    func speedDoesNotImplyCar() {
        let points = [
            point(north: 0, east: 0, minute: 0, speed: 22),
            point(north: 1_000, east: 0, minute: 1, speed: 24),
        ]
        #expect(
            JournalRecordingClassifier.dominantMode(
                motion: [],
                points: points
            ) == .unknown
        )
    }

    @Test("Transient durable states reject duplicate toggles")
    func transitionPolicy() {
        #expect(
            JournalRecordingStateMachine.action(
                for: nil,
                origin: .backgroundIntent
            ) == .start
        )
        #expect(
            JournalRecordingStateMachine.action(
                for: .starting,
                origin: .backgroundIntent
            ) == .wait
        )
        #expect(
            JournalRecordingStateMachine.action(
                for: .recording,
                origin: .backgroundIntent
            ) == .stop
        )
        #expect(
            JournalRecordingStateMachine.action(
                for: .stopping,
                origin: .foregroundIntent
            ) == .wait
        )
        #expect(
            JournalRecordingStateMachine.action(
                for: .awaitingForeground,
                origin: .backgroundIntent
            ) == .needsForeground
        )
        #expect(
            JournalRecordingStateMachine.action(
                for: .awaitingForeground,
                origin: .foregroundIntent
            ) == .resumeInForeground
        )
    }

    @Test("Finalization is idempotent after an entry was saved")
    @MainActor
    func idempotentFinalization() async throws {
        let schema = Schema([
            LogEntry.self,
            Person.self,
            Place.self,
            TransitDetails.self,
            PlaceVisitDetails.self,
            WorkoutDetails.self,
            ActiveJournalRecording.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let recording = ActiveJournalRecording(
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            status: .stopping,
            startPath: .foregroundFallback
        )
        let entry = LogEntry(
            kind: .transit,
            journalRecordingID: recording.id,
            needsReview: false
        )
        entry.transitDetails = TransitDetails(
            type: "Bicycle",
            recordedTransitMode: .cycling
        )
        context.insert(recording)
        context.insert(entry)
        try context.save()

        let result = try await JournalRecordingFinalizer().finalize(
            recording,
            in: context
        )

        #expect(result == .transit(.cycling))
        #expect(try context.fetchCount(FetchDescriptor<LogEntry>()) == 1)
    }

    private let baseLatitude = 44.4268
    private let baseLongitude = 26.1025

    private func latitude(north: Double) -> Double {
        baseLatitude + north / 111_132
    }

    private func point(
        north: Double,
        east: Double,
        minute: Double,
        accuracy: Double = 8,
        speed: Double? = nil
    ) -> TrackedLocationPoint {
        let longitudeScale = 111_320 * cos(baseLatitude * .pi / 180)
        return TrackedLocationPoint(
            latitude: latitude(north: north),
            longitude: baseLongitude + east / longitudeScale,
            timestamp: start.addingTimeInterval(minute * 60),
            horizontalAccuracy: accuracy,
            altitude: nil,
            speed: speed,
            course: nil
        )
    }
}
