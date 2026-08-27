import CoreLocation
import Testing

@testable import Journal

@Suite("Timeline workout card layout")
struct WorkoutCardLayoutTests {
    @Test("Place visits without people use one physical row")
    func compactPlaceVisit() {
        #expect(
            TimelinePlaceVisitCardLayout.rowCount(
                hasPeople: false,
                peopleNeedReview: false,
                photoCount: 2
            ) == 1
        )
        #expect(
            TimelinePlaceVisitCardLayout.rowCount(
                hasPeople: true,
                peopleNeedReview: false,
                photoCount: 0
            ) == 2
        )
        #expect(
            TimelinePlaceVisitCardLayout.rowCount(
                hasPeople: false,
                peopleNeedReview: true,
                photoCount: 0
            ) == 2
        )
        #expect(
            TimelinePlaceVisitCardLayout.rowCount(
                hasPeople: false,
                peopleNeedReview: false,
                photoCount: 3
            ) == 2
        )
    }

    @Test("Only compact place visits bias the map camera north")
    func compactPlaceVisitMapCameraBias() {
        let compactOffset = TimelinePlaceVisitCardLayout
            .mapCameraNorthOffsetFraction(rowCount: 1)
        let expandedOffset = TimelinePlaceVisitCardLayout
            .mapCameraNorthOffsetFraction(rowCount: 2)

        #expect(compactOffset > 0)
        #expect(expandedOffset == 0)
    }

    @Test("Place visit weather fills every row when people are absent")
    func placeVisitWeatherRowSpan() {
        #expect(
            TimelinePlaceVisitCardLayout.weatherRowCount(
                cardRowCount: 2,
                showsPeople: false
            ) == 2
        )
        #expect(
            TimelinePlaceVisitCardLayout.weatherRowCount(
                cardRowCount: 2,
                showsPeople: true
            ) == 1
        )
        #expect(
            TimelinePlaceVisitCardLayout.weatherRowCount(
                cardRowCount: 1,
                showsPeople: false
            ) == 1
        )
    }

    @Test("Only place visits needing review use an orange inner shadow")
    func placeVisitReviewInnerShadow() {
        #expect(
            TimelineEntryCardReviewPresentation.showsOrangeInnerShadow(
                kind: .placeVisit,
                needsReview: true
            )
        )
        #expect(
            !TimelineEntryCardReviewPresentation.showsOrangeInnerShadow(
                kind: .placeVisit,
                needsReview: false
            )
        )
        #expect(
            !TimelineEntryCardReviewPresentation.showsOrangeInnerShadow(
                kind: .transit,
                needsReview: true
            )
        )
    }

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
