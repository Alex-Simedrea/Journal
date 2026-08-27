import Foundation
import SwiftData
import Testing

@testable import Journal

@Suite("Timeline transit gaps")
@MainActor
struct TimelineTransitGapTests {
    @Test("Walking and car inference uses both distance and available time")
    func transitTypeInference() {
        #expect(
            TimelineTransitGapInference.transitType(
                distanceMeters: 1_000,
                duration: 15 * 60
            ) == "Walk"
        )
        #expect(
            TimelineTransitGapInference.transitType(
                distanceMeters: 1_000,
                duration: 4 * 60
            ) == "Car"
        )
        #expect(
            TimelineTransitGapInference.transitType(
                distanceMeters: 7_000,
                duration: 90 * 60
            ) == "Car"
        )
    }

    @Test("A draft fills visit boundaries and shared people before insertion")
    func preparedDraft() throws {
        let context = try makeContext()
        let shared = Person(name: "Shared")
        let originOnly = Person(name: "Origin only")
        let destinationOnly = Person(name: "Destination only")
        let originPlace = place(
            name: "Home",
            latitude: 44.430,
            longitude: 26.100
        )
        let destinationPlace = place(
            name: "Office",
            latitude: 44.440,
            longitude: 26.110
        )
        let origin = visit(
            start: 1_000,
            end: 2_000,
            place: originPlace,
            people: [shared, originOnly]
        )
        let destination = visit(
            start: 2_900,
            end: 4_000,
            place: destinationPlace,
            people: [shared, destinationOnly]
        )
        [shared, originOnly, destinationOnly].forEach(context.insert)
        [originPlace, destinationPlace].forEach(context.insert)
        [origin, destination].forEach(context.insert)
        try context.save()

        let gapID = TimelineTransitGapID(
            originVisitEntryID: origin.id,
            destinationVisitEntryID: destination.id
        )
        let draft = try TimelineTransitGapService.makeDraft(
            gapID: gapID,
            in: context
        )

        #expect(try context.fetch(FetchDescriptor<LogEntry>()).count == 2)
        #expect(draft.startTime == origin.endTime)
        #expect(draft.endTime == destination.startTime)
        #expect(draft.transitDetails?.originPlace?.id == originPlace.id)
        #expect(
            draft.transitDetails?.destinationPlace?.id
                == destinationPlace.id
        )
        #expect(Set(draft.people.map(\.id)) == [shared.id])
        #expect(draft.transitDetails?.type == "Walk")
        #expect(draft.startTimeZoneIdentifier == "Europe/Bucharest")
        #expect(draft.endTimeZoneIdentifier == "Europe/Paris")

        let insertedID = try TimelineTransitGapService.insert(
            draft,
            selectedPeopleIDs: [shared.id, destinationOnly.id],
            gapID: gapID,
            in: context
        )
        let transits = try context.fetch(FetchDescriptor<LogEntry>())
            .filter { $0.kind == .transit }
        let inserted = try #require(transits.first)

        #expect(transits.count == 1)
        #expect(inserted.id == insertedID)
        #expect(Set(inserted.people.map(\.id)) == [shared.id, destinationOnly.id])
    }

    @Test("An overlapping transit prevents draft preparation")
    func overlappingTransit() throws {
        let context = try makeContext()
        let originPlace = place(
            name: "Home",
            latitude: 44.430,
            longitude: 26.100
        )
        let destinationPlace = place(
            name: "Office",
            latitude: 44.440,
            longitude: 26.110
        )
        let origin = visit(
            start: 1_000,
            end: 2_000,
            place: originPlace
        )
        let destination = visit(
            start: 3_000,
            end: 4_000,
            place: destinationPlace
        )
        let existing = LogEntry(
            kind: .transit,
            startTime: Date(timeIntervalSince1970: 1_500),
            endTime: Date(timeIntervalSince1970: 2_500),
            needsReview: false
        )
        existing.transitDetails = TransitDetails(type: "Car")
        [originPlace, destinationPlace].forEach(context.insert)
        [origin, destination, existing].forEach(context.insert)
        try context.save()

        let gapID = TimelineTransitGapID(
            originVisitEntryID: origin.id,
            destinationVisitEntryID: destination.id
        )
        #expect(throws: (any Error).self) {
            _ = try TimelineTransitGapService.makeDraft(
                gapID: gapID,
                in: context
            )
        }
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            LogEntry.self,
            Person.self,
            Place.self,
            TransitDetails.self,
            PlaceVisitDetails.self,
            WorkoutDetails.self,
            TransitType.self,
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return ModelContext(container)
    }

    private func place(
        name: String,
        latitude: Double,
        longitude: Double
    ) -> Place {
        Place(
            name: name,
            location: Location(
                latitude: latitude,
                longitude: longitude,
                timeZoneIdentifier: name == "Home"
                    ? "Europe/Bucharest"
                    : "Europe/Paris"
            )
        )
    }

    private func visit(
        start: TimeInterval,
        end: TimeInterval,
        place: Place,
        people: [Person] = []
    ) -> LogEntry {
        let entry = LogEntry(
            kind: .placeVisit,
            startTime: Date(timeIntervalSince1970: start),
            endTime: Date(timeIntervalSince1970: end),
            startTimeZoneIdentifier: place.location.timeZoneIdentifier,
            endTimeZoneIdentifier: place.location.timeZoneIdentifier,
            timeConfidence: .explicit,
            needsReview: false
        )
        entry.placeVisitDetails = PlaceVisitDetails(place: place)
        entry.people = people
        return entry
    }
}
