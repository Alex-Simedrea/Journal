import CoreLocation
import Testing

@testable import Journal

@Suite("Timeline workout card layout")
struct WorkoutCardLayoutTests {
    @Test("Static workouts without people use one row")
    func compactStaticWorkout() {
        #expect(
            TimelineWorkoutCardLayout.rowCount(
                movementKind: .staticWorkout,
                hasPeople: false
            ) == 1
        )
    }

    @Test("Static workouts with people keep two rows")
    func staticWorkoutWithPeople() {
        #expect(
            TimelineWorkoutCardLayout.rowCount(
                movementKind: .staticWorkout,
                hasPeople: true
            ) == 2
        )
    }

    @Test("Moving and unresolved workouts keep two rows")
    func nonStaticWorkouts() {
        #expect(
            TimelineWorkoutCardLayout.rowCount(
                movementKind: .moving,
                hasPeople: false
            ) == 2
        )
        #expect(
            TimelineWorkoutCardLayout.rowCount(
                movementKind: nil,
                hasPeople: false
            ) == 2
        )
    }

    @Test("Compact static workout maps frame the place below center")
    func compactMapCameraBias() {
        let place = CLLocationCoordinate2D(
            latitude: 44.4268,
            longitude: 26.1025
        )
        let center = PlaceMapCamera.center(
            northOf: place,
            byMeters: 60
        )

        #expect(center.latitude > place.latitude)
        #expect(abs(center.longitude - place.longitude) < 0.000_001)
    }
}
