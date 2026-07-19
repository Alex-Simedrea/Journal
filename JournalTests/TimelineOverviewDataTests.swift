import CoreLocation
import Foundation
import Testing
@testable import Journal

struct TimelineOverviewDataTests {
    @Test func movingWorkoutUsesEveryExactRoutePoint() throws {
        let entryID = UUID()
        let start = try Date(
            "2026-07-19T08:00:00Z",
            strategy: .iso8601
        )
        let snapshot = TimelineEntrySnapshot(
            id: entryID,
            createdAt: start,
            startTime: start,
            endTime: start.addingTimeInterval(3_600),
            startTimeZoneIdentifier: "UTC",
            endTimeZoneIdentifier: "UTC",
            creationTimeZoneIdentifier: "UTC",
            timeConfidence: .explicit,
            kind: .workout,
            workoutActivityName: "Running",
            workoutMovementKind: .moving,
            workoutOrigin: "Start Place",
            workoutDestination: "End Place",
            workoutRouteStart: point(0),
            workoutRouteEnd: point(511)
        )
        let occurrence = try #require(
            TimelineProjection.project(
                entries: [snapshot],
                for: TimelineDayKey(year: 2026, month: 7, day: 19)
            ).occurrences.first
        )
        let route = (0..<512).map(point)

        let data = TimelineOverviewData.make(
            occurrences: [occurrence],
            workoutRoutes: [entryID: route]
        )

        let path = try #require(data.paths.first)
        #expect(path.kind == .workout)
        #expect(path.coordinates.count == route.count)
        #expect(path.coordinates[237].latitude == route[237].latitude)
        #expect(path.coordinates[237].longitude == route[237].longitude)
        #expect(data.markers.map(\.name).sorted() == ["End Place", "Start Place"])
        #expect(data.hasContent)
    }

    @Test func storedHealthKitEndpointsKeepWorkoutOnlyMapVisible() throws {
        let start = try Date(
            "2026-07-19T08:00:00Z",
            strategy: .iso8601
        )
        let snapshot = TimelineEntrySnapshot(
            createdAt: start,
            startTime: start,
            endTime: start.addingTimeInterval(1_800),
            startTimeZoneIdentifier: "UTC",
            endTimeZoneIdentifier: "UTC",
            creationTimeZoneIdentifier: "UTC",
            timeConfidence: .explicit,
            kind: .workout,
            workoutMovementKind: .moving,
            workoutRouteStart: point(0),
            workoutRouteEnd: point(1)
        )
        let occurrence = try #require(
            TimelineProjection.project(
                entries: [snapshot],
                for: TimelineDayKey(year: 2026, month: 7, day: 19)
            ).occurrences.first
        )

        let data = TimelineOverviewData.make(occurrences: [occurrence])

        #expect(data.paths.isEmpty)
        #expect(data.markers.count == 2)
        #expect(data.hasContent)
    }

    private func point(_ index: Int) -> WorkoutCoordinateSnapshot {
        WorkoutCoordinateSnapshot(
            latitude: 44.4 + Double(index) * 0.000_01,
            longitude: 26.1 + Double(index) * 0.000_01,
            horizontalAccuracyMeters: 2
        )
    }
}
