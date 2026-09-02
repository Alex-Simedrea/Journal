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

    @Test("An hour of stationary drift does not accumulate route distance")
    func stationaryDistanceIsStable() {
        let points = (0...60).map { minute in
            let angle = Double(minute) * 2.399
            return point(
                north: cos(angle) * 24,
                east: sin(angle) * 24,
                minute: Double(minute),
                accuracy: 8,
                speed: 0
            )
        }

        let distance = JournalRecordingClassifier.routeDistance(points)

        #expect(distance < 100)
    }

    @Test("Walking inside a saved venue remains a place visit")
    func savedVenueContainsInternalWalking() throws {
        let venueID = UUID()
        let points = [
            point(north: -70, east: -50, minute: 0, speed: 1.2),
            point(north: -70, east: 50, minute: 5, speed: 1.2),
            point(north: 70, east: 50, minute: 10, speed: 1.2),
            point(north: 70, east: -50, minute: 15, speed: 1.2),
            point(north: -70, east: -50, minute: 20, speed: 1.2),
        ]
        let motion = [
            RecordedMotionObservation(
                startTime: start,
                endTime: start.addingTimeInterval(20 * 60),
                kind: .walking,
                confidenceRawValue: 2
            )
        ]
        let venue = JournalRecordingPlaceRegion(
            id: venueID,
            name: "Shopping Centre",
            latitude: baseLatitude,
            longitude: baseLongitude,
            radiusMeters: 180,
            isHome: false
        )

        let result = try #require(
            JournalRecordingClassifier.classify(
                points: points,
                motion: motion,
                placeRegions: [venue]
            )
        )

        guard case .visit = result else {
            Issue.record("Expected the saved venue to contain the walk")
            return
        }
    }

    @Test("Continuous recording emits journeys and omits short Home boundaries")
    func continuousHomeBoundaries() {
        let homeID = UUID()
        let cafeID = UUID()
        var points: [TrackedLocationPoint] = (0...5).map {
            point(north: Double($0 % 2) * 3, east: 0, minute: Double($0))
        }
        points += [
            point(north: 300, east: 0, minute: 6, speed: 12),
            point(north: 1_000, east: 0, minute: 8, speed: 14),
            point(north: 2_000, east: 0, minute: 10, speed: 14),
            point(north: 3_000, east: 0, minute: 12, speed: 10),
        ]
        points += stride(from: 13.0, through: 43.0, by: 5).map {
            point(north: 3_000, east: $0.truncatingRemainder(dividingBy: 2) * 2, minute: $0)
        }
        points += [
            point(north: 2_400, east: 0, minute: 44, speed: 12),
            point(north: 1_500, east: 0, minute: 46, speed: 14),
            point(north: 500, east: 0, minute: 49, speed: 12),
        ]
        points += (51...56).map {
            point(north: Double($0 % 2) * 3, east: 0, minute: Double($0))
        }
        let motion = [
            RecordedMotionObservation(
                startTime: start.addingTimeInterval(5 * 60),
                endTime: start.addingTimeInterval(13 * 60),
                kind: .automotive,
                confidenceRawValue: 2
            ),
            RecordedMotionObservation(
                startTime: start.addingTimeInterval(43 * 60),
                endTime: start.addingTimeInterval(51 * 60),
                kind: .automotive,
                confidenceRawValue: 2
            ),
        ]
        let places = [
            region(id: homeID, name: "Home", north: 0, radius: 50, isHome: true),
            region(id: cafeID, name: "Cafe", north: 3_000, radius: 60),
        ]

        let segments = JournalRecordingSegmenter.segments(
            points: points,
            motion: motion,
            places: places
        )

        #expect(segments.count == 3)
        guard segments.count == 3 else { return }
        guard case .transit(let outbound) = segments[0],
              case .visit(let visit) = segments[1],
              case .transit(let inbound) = segments[2] else {
            Issue.record("Expected transit, visit, transit")
            return
        }
        #expect(outbound.originPlaceID == homeID)
        #expect(outbound.destinationPlaceID == cafeID)
        #expect(visit.placeID == cafeID)
        #expect(inbound.originPlaceID == cafeID)
        #expect(inbound.destinationPlaceID == homeID)
        #expect(outbound.mode == .automotive)
        #expect(inbound.mode == .automotive)
    }

    @Test("Precise points select the nearest of overlapping saved places")
    func preciseNearbyPlaces() {
        let firstID = UUID()
        let secondID = UUID()
        let points = (0...6).map { index in
            point(
                north: 1,
                east: 2 + Double(index % 2),
                minute: Double(index) * 2,
                accuracy: 5
            )
        }
        let places = [
            region(id: firstID, name: "First", north: 0, east: 0, radius: 50),
            region(id: secondID, name: "Second", north: 0, east: 24, radius: 50),
        ]

        let segments = JournalRecordingSegmenter.segments(
            points: points,
            motion: [],
            places: places
        )

        guard case .visit(let visit)? = segments.first else {
            Issue.record("Expected a saved-place visit")
            return
        }
        #expect(visit.placeID == firstID)
    }

    @Test("Nearby saved places remain distinct with a continuous short transit")
    func nearbyPlacesRemainContinuous() {
        let firstID = UUID()
        let secondID = UUID()
        var points = stride(from: 0.0, through: 10.0, by: 2).map {
            point(north: 0, east: 1, minute: $0, accuracy: 5)
        }
        points.append(
            point(north: 0, east: 15, minute: 11, accuracy: 5, speed: 1.2)
        )
        points += stride(from: 12.0, through: 22.0, by: 2).map {
            point(north: 0, east: 29, minute: $0, accuracy: 5)
        }
        let places = [
            region(id: firstID, name: "First", north: 0, east: 0, radius: 50),
            region(id: secondID, name: "Second", north: 0, east: 30, radius: 50),
        ]
        let motion = [
            RecordedMotionObservation(
                startTime: start.addingTimeInterval(10 * 60),
                endTime: start.addingTimeInterval(13 * 60),
                kind: .walking,
                confidenceRawValue: 2
            )
        ]

        let segments = JournalRecordingSegmenter.segments(
            points: points,
            motion: motion,
            places: places
        )

        #expect(segments.count == 3)
        guard segments.count == 3,
              case .visit(let first) = segments[0],
              case .transit(let transit) = segments[1],
              case .visit(let second) = segments[2] else { return }
        #expect(first.placeID == firstID)
        #expect(transit.originPlaceID == firstID)
        #expect(transit.destinationPlaceID == secondID)
        #expect(second.placeID == secondID)
    }

    @Test("Motion history splits consecutive transit modes")
    func motionSplitsMultimodalTransit() {
        let points = stride(from: 0.0, through: 42.0, by: 2).map { minute in
            let north: Double
            if minute <= 8 {
                north = minute * 35
            } else if minute <= 30 {
                north = 280 + (minute - 8) * 140
            } else {
                north = 3_360 + (minute - 30) * 35
            }
            return point(north: north, east: 0, minute: minute, accuracy: 7)
        }
        let motion = [
            RecordedMotionObservation(
                startTime: start,
                endTime: start.addingTimeInterval(8 * 60),
                kind: .walking,
                confidenceRawValue: 2
            ),
            RecordedMotionObservation(
                startTime: start.addingTimeInterval(8 * 60),
                endTime: start.addingTimeInterval(30 * 60),
                kind: .automotive,
                confidenceRawValue: 2
            ),
            RecordedMotionObservation(
                startTime: start.addingTimeInterval(30 * 60),
                endTime: start.addingTimeInterval(42 * 60),
                kind: .walking,
                confidenceRawValue: 2
            ),
        ]

        let segments = JournalRecordingSegmenter.segments(
            points: points,
            motion: motion,
            places: []
        )

        #expect(segments.count == 3)
        guard segments.count == 3,
              case .transit(let first) = segments[0],
              case .transit(let second) = segments[1],
              case .transit(let third) = segments[2] else { return }
        #expect([first.mode, second.mode, third.mode]
            == [.walking, .automotive, .walking])
        #expect(first.endTime == second.startTime)
        #expect(second.endTime == third.startTime)
        #expect(first.destination.latitude == second.origin.latitude)
        #expect(second.destination.latitude == third.origin.latitude)
    }

    @Test("Motion walking inside a saved venue does not create transit")
    func segmenterContainsWalkingInsideVenue() {
        let venueID = UUID()
        let points = [
            point(north: -70, east: -50, minute: 0, speed: 1.2),
            point(north: -70, east: 50, minute: 5, speed: 1.2),
            point(north: 70, east: 50, minute: 10, speed: 1.2),
            point(north: 70, east: -50, minute: 15, speed: 1.2),
            point(north: -70, east: -50, minute: 20, speed: 1.2),
        ]
        let motion = [
            RecordedMotionObservation(
                startTime: start,
                endTime: start.addingTimeInterval(20 * 60),
                kind: .walking,
                confidenceRawValue: 2
            )
        ]
        let venue = region(
            id: venueID,
            name: "Shopping Centre",
            north: 0,
            radius: 180
        )

        let segments = JournalRecordingSegmenter.segments(
            points: points,
            motion: motion,
            places: [venue]
        )

        #expect(segments.count == 1)
        guard case .visit(let visit)? = segments.first else {
            Issue.record("Expected one venue visit")
            return
        }
        #expect(visit.placeID == venueID)
    }

    @Test("CLVisit evidence can confirm a noisy stationary area")
    func visitEvidenceEnrichesNoisyDwell() {
        let points = (0...10).map { index in
            point(
                north: index.isMultiple(of: 2) ? -85 : 85,
                east: 0,
                minute: Double(index) * 2,
                accuracy: 40
            )
        }
        let evidence = JournalRecordingVisitEvidence(
            startTime: start,
            endTime: start.addingTimeInterval(20 * 60),
            latitude: baseLatitude,
            longitude: baseLongitude,
            horizontalAccuracyMeters: 40,
            placeID: nil
        )

        let segments = JournalRecordingSegmenter.segments(
            points: points,
            motion: [],
            places: [],
            visitEvidence: [evidence]
        )

        #expect(segments.count == 1)
        guard case .visit = segments.first else {
            Issue.record("Expected CLVisit plus GPS dwell to produce a visit")
            return
        }
    }

    @Test("A brief pass-through rejects false-positive CLVisit evidence")
    func visitEvidenceRejectsPassThrough() {
        let points = (0...10).map { index in
            point(
                north: Double(index) * 100,
                east: 0,
                minute: Double(index) * 2,
                accuracy: 8,
                speed: 4
            )
        }
        let evidence = JournalRecordingVisitEvidence(
            startTime: start,
            endTime: start.addingTimeInterval(20 * 60),
            latitude: latitude(north: 500),
            longitude: baseLongitude,
            horizontalAccuracyMeters: 40,
            placeID: nil
        )

        let segments = JournalRecordingSegmenter.segments(
            points: points,
            motion: [],
            places: [],
            visitEvidence: [evidence]
        )

        #expect(segments.count == 1)
        guard case .transit = segments.first else {
            Issue.record("Expected GPS movement to reject the visit evidence")
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

    private func region(
        id: UUID,
        name: String,
        north: Double,
        east: Double = 0,
        radius: Double,
        isHome: Bool = false
    ) -> JournalRecordingPlaceRegion {
        let longitudeScale = 111_320 * cos(baseLatitude * .pi / 180)
        return JournalRecordingPlaceRegion(
            id: id,
            name: name,
            latitude: latitude(north: north),
            longitude: baseLongitude + east / longitudeScale,
            radiusMeters: radius,
            isHome: isHome
        )
    }
}
