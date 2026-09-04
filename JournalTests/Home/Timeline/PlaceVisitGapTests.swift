import Foundation
import SwiftData
import Testing

@testable import Journal

@Suite("Timeline place visit gaps")
@MainActor
struct TimelinePlaceVisitGapTests {
    @Test("Home classification suppresses visits by name, not by icon")
    func homeExemption() {
        for (name, isHome) in [("Home", true), ("My HOME", true), ("Homewood", false)] {
            let place = Place(name: name, location: endpoint, systemImage: .house)
            let arrival = movement(start: 1_000, end: 2_000)
            let departure = movement(start: 2_900, end: 4_000)
            arrival.transitDetails?.destinationPlace = place
            departure.transitDetails?.originPlace = place
            #expect((gap(arrival, departure) == nil) == isHome)
        }
    }

    @Test("Long common-place gaps separate boundaries and keep only the arrival action")
    func longGap() throws {
        for name in ["Beach", "Home"] {
            let place = Place(name: name, location: endpoint)
            let arrival = movement(start: 1_000, end: 2_000)
            let departure = movement(start: 2_000 + 392 * 60, end: 27_000, workout: true)
            arrival.transitDetails?.destinationPlace = place
            departure.workoutDetails?.originPlace = place
            let rows = TimelineProjection.project(
                entries: [arrival, departure].map { TimelineEntrySnapshot(entry: $0) },
                for: TimelineDayKey(date: date(1_000), timeZone: .gmt)
            ).rows
            let destination = try #require(rows.first?.transitPresentation?.destination)
            let origin = try #require(rows.last?.transitPresentation?.origin)
            #expect(destination.showsPseudoEntry)
            #expect(destination.followingTransitStart == nil)
            #expect(origin.showsPseudoEntry)
            #expect(rows.last?.startBoundaryRenderedByPrevious == false)
            #expect(rows.last?.relationshipToPrevious == .gap(392 * 60))
            #expect(origin.placeVisitGapID == nil)
            if name == "Home" {
                #expect(destination.placeVisitGapID == nil)
            } else {
                #expect(destination.placeVisitGapID == gap(arrival, departure))
                #expect(destination.placeVisitGapID != nil)
            }
        }
    }

    @Test("Only a shared place with more than five free minutes offers a visit")
    func eligibility() {
        let arrival = movement(start: 1_000, end: 2_000)
        let exactlyFive = movement(start: 2_300, end: 3_000)
        let moreThanFive = movement(start: 2_301, end: 3_000)
        #expect(gap(arrival, exactlyFive) == nil)
        #expect(gap(arrival, moreThanFive) != nil)
        #expect(gap(arrival, movement(start: 1_999, end: 3_000)) == nil)

        let elsewhere = movement(start: 2_900, end: 3_000)
        elsewhere.transitDetails?.originLocation = Location(
            latitude: 46, longitude: 27)
        #expect(gap(arrival, elsewhere) == nil)

        let existing = LogEntry(
            kind: .placeVisit, startTime: date(2_100), endTime: date(2_200),
            needsReview: false)
        #expect(gap(arrival, moreThanFive, others: [existing]) == nil)
    }

    @Test(
        "The action belongs to the shared destination, including workout handoffs"
    )
    func projection() throws {
        let arrival = movement(start: 1_000, end: 2_000)
        let departure = movement(start: 2_900, end: 4_000, workout: true)
        let snapshots = [arrival, departure].map {
            TimelineEntrySnapshot(entry: $0)
        }
        let rows = TimelineProjection.project(
            entries: snapshots,
            for: TimelineDayKey(date: date(1_000), timeZone: .gmt)
        ).rows
        let destination = try #require(
            rows.first?.transitPresentation?.destination)
        #expect(destination.placeVisitGapID == gap(arrival, departure))
        #expect(destination.showsPseudoEntry)
        #expect(rows.last?.startBoundaryRenderedByPrevious == true)
    }

    @Test(
        "The detached draft fills place, times, zones, and the people intersection"
    )
    func draftAndSave() throws {
        let context = try makeContext()
        let shared = Person(name: "Shared")
        let arrivalOnly = Person(name: "Arrival only")
        let departureOnly = Person(name: "Departure only")
        let place = Place(name: "Beach", location: endpoint)
        let arrival = movement(start: 1_000, end: 2_000)
        let departure = movement(start: 2_900, end: 4_000, workout: true)
        arrival.transitDetails?.destinationPlace = place
        departure.workoutDetails?.originPlace = place
        arrival.people = [shared, arrivalOnly]
        departure.people = [shared, departureOnly]
        [shared, arrivalOnly, departureOnly].forEach(context.insert)
        context.insert(place)
        [arrival, departure].forEach(context.insert)
        try context.save()
        let id = try #require(gap(arrival, departure))
        let draft = try TimelinePlaceVisitGapService.makeDraft(
            gapID: id, in: context)
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).count == 2)
        #expect(draft.placeVisitDetails?.place?.id == place.id)
        #expect(
            draft.placeVisitDetails?.location?.formattedAddress
                == endpoint.formattedAddress)
        #expect(draft.startTime == arrival.endTime)
        #expect(draft.endTime == departure.startTime)
        #expect(draft.startTimeZoneIdentifier == arrival.endTimeZoneIdentifier)
        #expect(
            draft.endTimeZoneIdentifier == departure.startTimeZoneIdentifier)
        #expect(draft.people.map(\.id) == [shared.id])
        #expect(draft.people.first !== shared)

        let savedID = try TimelinePlaceVisitGapService.insert(
            draft, selectedPeopleIDs: [shared.id, departureOnly.id], gapID: id,
            in: context
        )
        #expect(savedID == draft.id)
        #expect(Set(draft.people.map(\.id)) == [shared.id, departureOnly.id])
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).count == 3)
        #expect(throws: (any Error).self) {
            try TimelinePlaceVisitGapService.makeDraft(gapID: id, in: context)
        }
    }

    @Test("Saving revalidates the gap after another visit is added")
    func staleDraft() throws {
        let context = try makeContext()
        let arrival = movement(start: 1_000, end: 2_000)
        let departure = movement(start: 2_900, end: 4_000)
        [arrival, departure].forEach(context.insert)
        try context.save()
        let id = try #require(gap(arrival, departure))
        let draft = try TimelinePlaceVisitGapService.makeDraft(
            gapID: id, in: context)
        let existing = LogEntry(
            kind: .placeVisit, startTime: date(2_100), endTime: date(2_200),
            needsReview: false)
        existing.placeVisitDetails = PlaceVisitDetails(location: endpoint)
        context.insert(existing)
        try context.save()
        #expect(throws: (any Error).self) {
            try TimelinePlaceVisitGapService.insert(
                draft, selectedPeopleIDs: [], gapID: id, in: context)
        }
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).count == 3)
    }

    private var endpoint: Location {
        Location(
            latitude: 44.43, longitude: 26.10, displayName: "Beach",
            systemImage: .mappin,
            formattedAddress: "1 Beach Road", timeZoneIdentifier: "UTC")
    }

    private func movement(start: Double, end: Double, workout: Bool = false)
        -> LogEntry
    {
        let entry = LogEntry(
            kind: workout ? .workout : .transit,
            startTime: date(start), endTime: date(end),
            startTimeZoneIdentifier: "UTC", endTimeZoneIdentifier: "UTC",
            needsReview: false
        )
        if workout {
            entry.workoutDetails = WorkoutDetails(
                healthKitWorkoutUUID: UUID(), activityTypeRawValue: 37,
                activityName: "Run", movementKind: .moving,
                originLocation: endpoint,
                destinationLocation: Location(latitude: 45, longitude: 27)
            )
        } else {
            entry.transitDetails = TransitDetails(
                type: "Car", originLocation: endpoint,
                destinationLocation: endpoint)
        }
        return entry
    }

    private func gap(
        _ arrival: LogEntry, _ departure: LogEntry, others: [LogEntry] = []
    )
        -> TimelinePlaceVisitGapID?
    {
        TimelinePlaceVisitGapInference.gapID(
            after: TimelineEntrySnapshot(entry: arrival),
            before: TimelineEntrySnapshot(entry: departure),
            entries: ([arrival, departure] + others).map {
                TimelineEntrySnapshot(entry: $0)
            }
        )
    }

    private func date(_ seconds: Double) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            LogEntry.self, Person.self, Place.self, TransitDetails.self,
            PlaceVisitDetails.self,
            WorkoutDetails.self, TransitType.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }
}
