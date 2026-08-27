import Foundation
import Testing

@testable import Journal

@Suite("Transit timeline continuity")
@MainActor
struct TransitContinuityTests {
    private let timeZoneIdentifier = "Europe/Bucharest"

    @Test("A gap between consecutive visits offers one transit action")
    func visitGapAction() throws {
        let home = location(name: "Home", latitude: 44.43, longitude: 26.10)
        let office = location(
            name: "Office",
            latitude: 44.44,
            longitude: 26.11
        )
        let first = placeVisit(
            start: "2026-07-17T09:00:00+03:00",
            end: "2026-07-17T10:00:00+03:00",
            location: home
        )
        let second = placeVisit(
            start: "2026-07-17T10:20:00+03:00",
            end: "2026-07-17T12:00:00+03:00",
            location: office
        )

        let gap = try #require(
            project([first, second]).rows.last?.transitGap
        )
        #expect(gap.id.originVisitEntryID == first.id)
        #expect(gap.id.destinationVisitEntryID == second.id)
    }

    @Test("A transit spanning the visit gap suppresses the action")
    func overlappingTransitSuppressesGapAction() {
        let home = location(name: "Home", latitude: 44.43, longitude: 26.10)
        let office = location(
            name: "Office",
            latitude: 44.44,
            longitude: 26.11
        )
        let spanningTransit = transit(
            start: "2026-07-17T08:30:00+03:00",
            end: "2026-07-17T10:10:00+03:00",
            origin: home,
            destination: office
        )
        let first = placeVisit(
            start: "2026-07-17T09:00:00+03:00",
            end: "2026-07-17T10:00:00+03:00",
            location: home
        )
        let second = placeVisit(
            start: "2026-07-17T10:20:00+03:00",
            end: "2026-07-17T12:00:00+03:00",
            location: office
        )

        #expect(
            project([spanningTransit, first, second])
                .rows.last?.transitGap == nil
        )
    }

    @Test("Matching neighbors suppress both pseudo-place rows")
    func fullyMatchingContinuity() throws {
        let home = location(name: "Home", latitude: 44.43, longitude: 26.10)
        let office = location(
            name: "Office",
            latitude: 44.44,
            longitude: 26.11
        )
        let previous = placeVisit(
            start: "2026-07-17T09:00:00+03:00",
            end: "2026-07-17T10:00:05+03:00",
            location: home
        )
        let transit = transit(
            start: "2026-07-17T10:00:52+03:00",
            end: "2026-07-17T10:30:00+03:00",
            origin: home,
            destination: office
        )
        let next = placeVisit(
            start: "2026-07-17T10:30:30+03:00",
            end: "2026-07-17T12:00:00+03:00",
            location: office
        )

        let presentation = try #require(
            project([previous, transit, next])
                .rows.first { $0.occurrence.entryID == transit.id }?
                .transitPresentation
        )

        #expect(!presentation.origin.showsPseudoEntry)
        #expect(!presentation.destination.showsPseudoEntry)
    }

    @Test("Each mismatched boundary independently adds a pseudo-place row")
    func independentBoundaryMismatches() throws {
        let home = location(name: "Home", latitude: 44.43, longitude: 26.10)
        let office = location(
            name: "Office",
            latitude: 44.44,
            longitude: 26.11
        )
        let elsewhere = location(
            name: "Elsewhere",
            latitude: 44.50,
            longitude: 26.20
        )

        let originMismatch = try presentation(
            previous: placeVisit(
                start: "2026-07-17T09:00:00+03:00",
                end: "2026-07-17T10:00:00+03:00",
                location: elsewhere
            ),
            transit: transit(
                start: "2026-07-17T10:00:00+03:00",
                end: "2026-07-17T10:30:00+03:00",
                origin: home,
                destination: office
            ),
            next: placeVisit(
                start: "2026-07-17T10:30:00+03:00",
                end: "2026-07-17T12:00:00+03:00",
                location: office
            )
        )
        #expect(originMismatch.origin.showsPseudoEntry)
        #expect(!originMismatch.destination.showsPseudoEntry)

        let destinationMismatch = try presentation(
            previous: placeVisit(
                start: "2026-07-17T09:00:00+03:00",
                end: "2026-07-17T10:00:00+03:00",
                location: home
            ),
            transit: transit(
                start: "2026-07-17T10:00:00+03:00",
                end: "2026-07-17T10:30:00+03:00",
                origin: home,
                destination: office
            ),
            next: placeVisit(
                start: "2026-07-17T10:30:00+03:00",
                end: "2026-07-17T12:00:00+03:00",
                location: elsewhere
            )
        )
        #expect(!destinationMismatch.origin.showsPseudoEntry)
        #expect(destinationMismatch.destination.showsPseudoEntry)

        let transitWithoutNeighbors = transit(
            start: "2026-07-17T10:00:00+03:00",
            end: "2026-07-17T10:30:00+03:00",
            origin: home,
            destination: office
        )
        let both = try #require(
            project([transitWithoutNeighbors]).rows.first?.transitPresentation
        )
        #expect(both.origin.showsPseudoEntry)
        #expect(both.destination.showsPseudoEntry)
    }

    @Test("A time mismatch creates a pseudo row even when the place matches")
    func timeMismatch() throws {
        let home = location(name: "Home", latitude: 44.43, longitude: 26.10)
        let office = location(
            name: "Office",
            latitude: 44.44,
            longitude: 26.11
        )
        let result = try presentation(
            previous: placeVisit(
                start: "2026-07-17T09:00:00+03:00",
                end: "2026-07-17T09:58:59+03:00",
                location: home
            ),
            transit: transit(
                start: "2026-07-17T10:00:00+03:00",
                end: "2026-07-17T10:30:00+03:00",
                origin: home,
                destination: office
            ),
            next: placeVisit(
                start: "2026-07-17T10:30:00+03:00",
                end: "2026-07-17T12:00:00+03:00",
                location: office
            )
        )

        #expect(result.origin.showsPseudoEntry)
        #expect(!result.destination.showsPseudoEntry)
    }

    @Test("Saved place IDs are authoritative")
    func savedPlaceIdentity() {
        let sharedID = UUID()
        let sameSavedPlaceA = location(
            savedPlaceID: sharedID,
            name: "Home",
            latitude: 44.43,
            longitude: 26.10
        )
        let sameSavedPlaceB = location(
            savedPlaceID: sharedID,
            name: "Acasă",
            latitude: 45,
            longitude: 27
        )
        let differentSavedPlace = location(
            savedPlaceID: UUID(),
            name: "Home",
            latitude: 44.43,
            longitude: 26.10
        )

        #expect(
            TimelineBoundaryMatcher.locationsMatch(
                sameSavedPlaceA,
                sameSavedPlaceB
            )
        )
        #expect(
            !TimelineBoundaryMatcher.locationsMatch(
                sameSavedPlaceA,
                differentSavedPlace
            )
        )
    }

    @Test("Unsaved locations use exact or nearby semantic matches")
    func semanticLocationMatching() {
        let exact = location(
            name: "Café Nord",
            latitude: 44.4300,
            longitude: 26.1000
        )
        let nearby = location(
            name: "cafe, nord",
            latitude: 44.4302,
            longitude: 26.1000
        )
        let distant = location(
            name: "Cafe Nord",
            latitude: 44.4400,
            longitude: 26.1000
        )
        let nameOnly = location(name: "cafe nord")

        #expect(TimelineBoundaryMatcher.locationsMatch(exact, exact))
        #expect(TimelineBoundaryMatcher.locationsMatch(exact, nearby))
        #expect(!TimelineBoundaryMatcher.locationsMatch(exact, distant))
        #expect(TimelineBoundaryMatcher.locationsMatch(exact, nameOnly))
    }

    @Test("The immediate locationless entry is not skipped")
    func locationlessAdjacency() throws {
        let home = location(name: "Home", latitude: 44.43, longitude: 26.10)
        let office = location(
            name: "Office",
            latitude: 44.44,
            longitude: 26.11
        )
        let visit = placeVisit(
            start: "2026-07-17T08:00:00+03:00",
            end: "2026-07-17T09:00:00+03:00",
            location: home
        )
        let wakeUp = snapshot(
            kind: .wakeUp,
            start: "2026-07-17T09:00:00+03:00",
            end: "2026-07-17T09:59:30+03:00"
        )
        let trip = transit(
            start: "2026-07-17T10:00:00+03:00",
            end: "2026-07-17T10:30:00+03:00",
            origin: home,
            destination: office
        )

        let result = try #require(
            project([visit, wakeUp, trip])
                .rows.first { $0.occurrence.entryID == trip.id }?
                .transitPresentation
        )
        #expect(result.origin.showsPseudoEntry)
    }

    @Test("Transit and workouts expose the correct adjacent endpoint")
    func neighboringEndpointKinds() throws {
        let home = location(name: "Home", latitude: 44.43, longitude: 26.10)
        let station = location(
            name: "Station",
            latitude: 44.44,
            longitude: 26.11
        )
        let beach = location(
            name: "Beach",
            latitude: 44.45,
            longitude: 26.12
        )
        let firstTrip = transit(
            start: "2026-07-17T09:00:00+03:00",
            end: "2026-07-17T10:00:00+03:00",
            origin: home,
            destination: station
        )
        let secondTrip = transit(
            start: "2026-07-17T10:00:00+03:00",
            end: "2026-07-17T11:00:00+03:00",
            origin: station,
            destination: beach
        )
        let movingWorkout = snapshot(
            kind: .workout,
            start: "2026-07-17T11:00:00+03:00",
            end: "2026-07-17T12:00:00+03:00",
            workoutMovementKind: .moving,
            workoutOriginLocation: beach,
            workoutDestinationLocation: home
        )

        let result = try #require(
            project([firstTrip, secondTrip, movingWorkout])
                .rows.first { $0.occurrence.entryID == secondTrip.id }?
                .transitPresentation
        )
        #expect(!result.origin.showsPseudoEntry)
        #expect(!result.destination.showsPseudoEntry)
    }

    @Test("Separated transits share one place between both timestamps")
    func separatedTransitHandoff() throws {
        let home = location(name: "Home", latitude: 44.43, longitude: 26.10)
        let station = location(
            name: "Gara Brașov",
            latitude: 45.66,
            longitude: 25.61
        )
        let northStation = location(
            name: "Gara de Nord",
            latitude: 44.45,
            longitude: 26.08
        )
        let bolt = transit(
            start: "2026-07-17T08:52:00+03:00",
            end: "2026-07-17T09:00:00+03:00",
            origin: home,
            destination: station
        )
        let train = transit(
            start: "2026-07-17T09:15:00+03:00",
            end: "2026-07-17T12:02:00+03:00",
            origin: station,
            destination: northStation
        )
        let rows = project([bolt, train]).rows
        let boltRow = try #require(
            rows.first { $0.occurrence.entryID == bolt.id }
        )
        let trainRow = try #require(
            rows.first { $0.occurrence.entryID == train.id }
        )
        let boltPresentation = try #require(
            boltRow.transitPresentation
        )
        let trainPresentation = try #require(
            trainRow.transitPresentation
        )
        let continuation = try #require(
            boltPresentation.destination.followingTransitStart
        )

        #expect(boltPresentation.destination.showsPseudoEntry)
        #expect(!trainPresentation.origin.showsPseudoEntry)
        #expect(trainRow.startBoundaryRenderedByPrevious)
        #expect(continuation.date == date("2026-07-17T09:15:00+03:00"))
    }

    @Test("Contiguous transits still show their shared place once")
    func contiguousTransitHandoff() throws {
        let station = location(
            name: "Gara de Nord",
            latitude: 44.45,
            longitude: 26.08
        )
        let center = location(
            name: "City center",
            latitude: 44.43,
            longitude: 26.10
        )
        let train = transit(
            start: "2026-07-17T09:15:00+03:00",
            end: "2026-07-17T12:02:00+03:00",
            origin: location(name: "Gara Brașov"),
            destination: station
        )
        let metro = transit(
            start: "2026-07-17T12:02:30+03:00",
            end: "2026-07-17T13:00:00+03:00",
            origin: station,
            destination: center
        )
        let rows = project([train, metro]).rows
        let trainRow = try #require(
            rows.first { $0.occurrence.entryID == train.id }
        )
        let metroRow = try #require(
            rows.first { $0.occurrence.entryID == metro.id }
        )
        let trainPresentation = try #require(
            trainRow.transitPresentation
        )
        let metroPresentation = try #require(
            metroRow.transitPresentation
        )
        let continuation = try #require(
            trainPresentation.destination.followingTransitStart
        )

        #expect(trainPresentation.destination.showsPseudoEntry)
        #expect(!metroPresentation.origin.showsPseudoEntry)
        #expect(metroRow.relationshipToPrevious == .contiguous)
        #expect(metroRow.startBoundaryRenderedByPrevious)
        #expect(continuation.date == date("2026-07-17T12:02:30+03:00"))
    }

    @Test("Contiguous transits with different places keep distinct boundaries")
    func contiguousTransitLocationMismatch() throws {
        let firstDestination = location(
            name: "Piazza Bra",
            latitude: 45.4380,
            longitude: 10.9921
        )
        let secondOrigin = location(
            name: "Piazza Broilo 3",
            latitude: 45.4432,
            longitude: 10.9987
        )
        let first = transit(
            start: "2026-07-17T17:52:00+03:00",
            end: "2026-07-17T18:10:00+03:00",
            origin: location(name: "Previous place"),
            destination: firstDestination
        )
        let second = transit(
            start: "2026-07-17T18:10:00+03:00",
            end: "2026-07-17T18:18:00+03:00",
            origin: secondOrigin,
            destination: firstDestination
        )
        let rows = project([first, second]).rows
        let firstRow = try #require(
            rows.first { $0.occurrence.entryID == first.id }
        )
        let secondRow = try #require(
            rows.first { $0.occurrence.entryID == second.id }
        )
        let firstPresentation = try #require(firstRow.transitPresentation)
        let secondPresentation = try #require(secondRow.transitPresentation)

        #expect(firstPresentation.destination.showsPseudoEntry)
        #expect(secondPresentation.origin.showsPseudoEntry)
        #expect(secondRow.relationshipToPrevious == .contiguous)
        #expect(secondRow.presentsDistinctContiguousTransitStart)
    }

    @Test("A static workout exposes the same place at both boundaries")
    func staticWorkoutBoundary() throws {
        let gym = location(name: "Gym", latitude: 44.43, longitude: 26.10)
        let office = location(
            name: "Office",
            latitude: 44.44,
            longitude: 26.11
        )
        let workout = snapshot(
            kind: .workout,
            start: "2026-07-17T09:00:00+03:00",
            end: "2026-07-17T10:00:00+03:00",
            workoutMovementKind: .staticWorkout,
            workoutPlaceLocation: gym
        )
        let trip = transit(
            start: "2026-07-17T10:00:00+03:00",
            end: "2026-07-17T10:30:00+03:00",
            origin: gym,
            destination: office
        )

        let result = try #require(
            project([workout, trip])
                .rows.first { $0.occurrence.entryID == trip.id }?
                .transitPresentation
        )
        #expect(!result.origin.showsPseudoEntry)
    }

    @Test("Intermediate days repeat the stored trip endpoints")
    func multiDayTransit() throws {
        let home = location(name: "Home", latitude: 44.43, longitude: 26.10)
        let beach = location(
            name: "Beach",
            latitude: 44.45,
            longitude: 26.12
        )
        let trip = transit(
            start: "2026-07-17T22:00:00+03:00",
            end: "2026-07-19T02:00:00+03:00",
            origin: home,
            destination: beach
        )
        let projection = TimelineProjection.project(
            entries: [trip],
            for: TimelineDayKey(year: 2026, month: 7, day: 18)
        )
        let result = try #require(
            projection.rows.first?.transitPresentation
        )

        #expect(result.origin.showsPseudoEntry)
        #expect(result.destination.showsPseudoEntry)
        #expect(result.origin.name == "Home")
        #expect(result.destination.name == "Beach")
    }

    @Test("Review badges stay with the field that can render them")
    func reviewPlacement() throws {
        let home = location(name: "Home", latitude: 44.43, longitude: 26.10)
        let office = location(
            name: "Office",
            latitude: 44.44,
            longitude: 26.11
        )
        let previous = placeVisit(
            start: "2026-07-17T09:00:00+03:00",
            end: "2026-07-17T10:00:00+03:00",
            location: home
        )
        let next = placeVisit(
            start: "2026-07-17T10:30:00+03:00",
            end: "2026-07-17T12:00:00+03:00",
            location: home
        )
        let trip = transit(
            start: "2026-07-17T10:00:00+03:00",
            end: "2026-07-17T10:30:00+03:00",
            origin: home,
            destination: office,
            reviews: [
                TimelineReviewSnapshot(
                    target: .origin,
                    reason: "Check origin"
                ),
                TimelineReviewSnapshot(
                    target: .destination,
                    reason: "Check destination"
                ),
            ]
        )

        let result = try #require(
            project([previous, trip, next])
                .rows.first { $0.occurrence.entryID == trip.id }?
                .transitPresentation
        )
        #expect(!result.origin.showsPseudoEntry)
        #expect(result.destination.showsPseudoEntry)
        #expect(result.showsReviewBadge)
    }

    @Test("A transit time review is retained on a shared timestamp")
    func sharedTimestampReview() throws {
        let home = location(name: "Home", latitude: 44.43, longitude: 26.10)
        let office = location(
            name: "Office",
            latitude: 44.44,
            longitude: 26.11
        )
        let previous = placeVisit(
            start: "2026-07-17T09:00:00+03:00",
            end: "2026-07-17T10:00:00+03:00",
            location: home
        )
        let trip = transit(
            start: "2026-07-17T10:00:30+03:00",
            end: "2026-07-17T10:30:00+03:00",
            origin: home,
            destination: office,
            reviews: [
                TimelineReviewSnapshot(
                    target: .time,
                    reason: "Check time"
                ),
            ]
        )
        let rows = project([previous, trip]).rows
        let previousRow = try #require(
            rows.first { $0.occurrence.entryID == previous.id }
        )
        let transitRow = try #require(
            rows.first { $0.occurrence.entryID == trip.id }
        )
        let transitPresentation = try #require(
            transitRow.transitPresentation
        )

        #expect(transitRow.relationshipToPrevious == .contiguous)
        #expect(!previousRow.endBoundaryNeedsReview)
        #expect(transitPresentation.showsReviewBadge)
    }

    @Test("Pseudo-place identity survives presentation edits")
    func stableBoundaryIdentity() throws {
        let entryID = UUID()
        let first = transit(
            id: entryID,
            start: "2026-07-17T10:00:00+03:00",
            end: "2026-07-17T10:30:00+03:00",
            origin: location(name: "Home"),
            destination: location(name: "Office")
        )
        let edited = transit(
            id: entryID,
            start: "2026-07-17T10:00:00+03:00",
            end: "2026-07-17T10:30:00+03:00",
            origin: location(name: "Acasă"),
            destination: location(name: "Work")
        )
        let firstPresentation = try #require(
            project([first]).rows.first?.transitPresentation
        )
        let editedPresentation = try #require(
            project([edited]).rows.first?.transitPresentation
        )

        #expect(firstPresentation.origin.id == editedPresentation.origin.id)
        #expect(
            firstPresentation.destination.id
                == editedPresentation.destination.id
        )
        #expect(firstPresentation.origin.id != firstPresentation.destination.id)
    }

    private func presentation(
        previous: TimelineEntrySnapshot,
        transit: TimelineEntrySnapshot,
        next: TimelineEntrySnapshot
    ) throws -> TimelineTransitRowPresentation {
        try #require(
            project([previous, transit, next])
                .rows.first { $0.occurrence.entryID == transit.id }?
                .transitPresentation
        )
    }

    private func project(
        _ entries: [TimelineEntrySnapshot]
    ) -> TimelineProjection {
        TimelineProjection.project(
            entries: entries,
            for: TimelineDayKey(year: 2026, month: 7, day: 17)
        )
    }

    private func transit(
        id: UUID = UUID(),
        start: String,
        end: String,
        origin: TimelineLocationSnapshot,
        destination: TimelineLocationSnapshot,
        reviews: [TimelineReviewSnapshot] = []
    ) -> TimelineEntrySnapshot {
        snapshot(
            id: id,
            kind: .transit,
            start: start,
            end: end,
            origin: origin.name,
            destination: destination.name,
            originLocation: origin,
            destinationLocation: destination,
            reviews: reviews
        )
    }

    private func placeVisit(
        start: String,
        end: String,
        location: TimelineLocationSnapshot
    ) -> TimelineEntrySnapshot {
        snapshot(
            kind: .placeVisit,
            start: start,
            end: end,
            visitPlace: location.name,
            visitLocation: location
        )
    }

    private func snapshot(
        id: UUID = UUID(),
        kind: LogKind,
        start: String,
        end: String,
        origin: String = "Origin",
        destination: String = "Destination",
        originLocation: TimelineLocationSnapshot? = nil,
        destinationLocation: TimelineLocationSnapshot? = nil,
        visitPlace: String = "Place",
        visitLocation: TimelineLocationSnapshot? = nil,
        workoutMovementKind: WorkoutMovementKind? = nil,
        workoutOriginLocation: TimelineLocationSnapshot? = nil,
        workoutDestinationLocation: TimelineLocationSnapshot? = nil,
        workoutPlaceLocation: TimelineLocationSnapshot? = nil,
        reviews: [TimelineReviewSnapshot] = []
    ) -> TimelineEntrySnapshot {
        let startDate = date(start)
        return TimelineEntrySnapshot(
            id: id,
            createdAt: startDate,
            startTime: startDate,
            endTime: date(end),
            startTimeZoneIdentifier: timeZoneIdentifier,
            endTimeZoneIdentifier: timeZoneIdentifier,
            creationTimeZoneIdentifier: timeZoneIdentifier,
            timeConfidence: .explicit,
            needsReview: !reviews.isEmpty,
            kind: kind,
            origin: origin,
            destination: destination,
            originLocation: originLocation,
            destinationLocation: destinationLocation,
            visitPlace: visitPlace,
            visitLocation: visitLocation,
            workoutMovementKind: workoutMovementKind,
            workoutOriginLocation: workoutOriginLocation,
            workoutDestinationLocation: workoutDestinationLocation,
            workoutPlaceLocation: workoutPlaceLocation,
            reviews: reviews
        )
    }

    private func location(
        savedPlaceID: UUID? = nil,
        name: String,
        latitude: Double = 0,
        longitude: Double = 0
    ) -> TimelineLocationSnapshot {
        TimelineLocationSnapshot(
            savedPlaceID: savedPlaceID,
            name: name,
            latitude: latitude,
            longitude: longitude,
            systemImage: name == "Home" ? .house : .mappin
        )
    }

    private func date(_ value: String) -> Date {
        do {
            return try Date(value, strategy: .iso8601)
        } catch {
            Issue.record("Could not parse test date: \(value)")
            return .distantPast
        }
    }
}
