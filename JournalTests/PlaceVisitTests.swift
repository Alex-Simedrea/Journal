import Foundation
import SwiftData
import Testing

@testable import Journal

@Suite("Place visits")
@MainActor
struct PlaceVisitTests {
    @Test("Visit storage snapshots its timezone and original input")
    func visitStorage() throws {
        let context = try makeContext()
        let place = Place(
            name: "Kasho",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: "Europe/Bucharest"
            )
        )
        context.insert(place)
        let draft = ResolvedPlaceVisitDraft(
            place: place,
            placeRawText: "kasho",
            startTime: date("2026-07-17T10:00:00+03:00"),
            endTime: date("2026-07-17T11:00:00+03:00"),
            timeConfidence: .explicit,
            people: [],
            candidates: [],
            unresolvedPeople: [],
            fieldReviews: [],
            entryKindReviewReason: nil
        )
        let entry = try PlaceVisitEntryStore.insert(
            draft: draft,
            rawInput: "At kasho from 10 to 11",
            in: context
        )

        #expect(entry.kind == .placeVisit)
        #expect(entry.startTimeZoneIdentifier == "Europe/Bucharest")
        #expect(entry.endTimeZoneIdentifier == "Europe/Bucharest")
        #expect(entry.rawInputString == "At kasho from 10 to 11")
    }

    @Test("Derived statistics follow edits, conversion review, and deletion")
    func derivedStatistics() {
        let firstPlace = Place(
            name: "First",
            location: Location(latitude: 45, longitude: 25)
        )
        let secondPlace = Place(
            name: "Second",
            location: Location(latitude: 46, longitude: 26)
        )
        let first = visitEntry(
            place: firstPlace,
            start: date("2026-07-16T10:00:00Z"),
            end: date("2026-07-16T11:00:00Z")
        )
        let second = visitEntry(place: firstPlace, start: nil, end: nil)

        var statistics = PlaceVisitStatisticsService.calculate(
            from: [first, second]
        )
        #expect(statistics[firstPlace.id]?.visitCount == 2)
        #expect(statistics[firstPlace.id]?.lastVisitedAt == first.endTime)

        second.placeVisitDetails?.place = secondPlace
        statistics = PlaceVisitStatisticsService.calculate(from: [first, second])
        #expect(statistics[firstPlace.id]?.visitCount == 1)
        #expect(statistics[secondPlace.id]?.visitCount == 1)

        second.entryKindReviewReason = "Ambiguous"
        statistics = PlaceVisitStatisticsService.calculate(from: [first, second])
        #expect(statistics[secondPlace.id] == nil)
        statistics = PlaceVisitStatisticsService.calculate(from: [second])
        #expect(statistics[firstPlace.id] == nil)
    }

    @Test("Place visits use the existing multi-day timeline projection")
    func visitTimelineProjection() {
        let snapshot = TimelineEntrySnapshot(
            createdAt: date("2026-07-17T08:00:00+03:00"),
            startTime: date("2026-07-17T22:00:00+03:00"),
            endTime: date("2026-07-18T02:00:00+03:00"),
            startTimeZoneIdentifier: "Europe/Bucharest",
            endTimeZoneIdentifier: "Europe/Bucharest",
            creationTimeZoneIdentifier: "Europe/Bucharest",
            timeConfidence: .explicit,
            kind: .placeVisit,
            visitPlace: "Home",
            visitSystemImage: .house
        )
        let first = TimelineProjection.project(
            entries: [snapshot],
            for: TimelineDayKey(year: 2026, month: 7, day: 17)
        )
        let second = TimelineProjection.project(
            entries: [snapshot],
            for: TimelineDayKey(year: 2026, month: 7, day: 18)
        )
        #expect(first.occurrences.first?.kind == .placeVisit)
        #expect(first.occurrences.first?.visitPlace == "Home")
        #expect(second.occurrences.count == 1)
    }

    @Test("Entry-kind conversion preserves shared entry metadata")
    func entryKindConversion() throws {
        let context = try makeContext()
        let origin = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.60)
        )
        let destination = Place(
            name: "Kasho",
            location: Location(latitude: 45.66, longitude: 25.59)
        )
        let person = Person(name: "Alex")
        let entry = visitEntry(
            place: destination,
            start: date("2026-07-17T10:00:00+03:00"),
            end: date("2026-07-17T11:00:00+03:00")
        )
        entry.rawInputString = "Ambiguous input"
        entry.photoReferences = [
            PhotoReference(assetLocalIdentifier: "asset"),
        ]
        entry.people = [person]
        entry.entryKindReviewReason = "Could be transit."
        entry.needsReview = true
        context.insert(origin)
        context.insert(destination)
        context.insert(person)
        context.insert(entry)
        try context.save()

        let toTransit = EntryKindConversionModel(
            entry: entry,
            targetKind: .transit
        )
        toTransit.transitType = "Walk"
        toTransit.originPlaceID = origin.id
        toTransit.destinationPlaceID = destination.id
        #expect(
            toTransit.save(
                entry: entry,
                places: [origin, destination],
                people: [person],
                in: context
            )
        )
        #expect(entry.kind == .transit)
        #expect(entry.transitDetails?.destinationPlace?.id == destination.id)
        #expect(entry.placeVisitDetails == nil)
        #expect(entry.rawInputString == "Ambiguous input")
        #expect(entry.photoReferences.first?.assetLocalIdentifier == "asset")

        let toVisit = EntryKindConversionModel(
            entry: entry,
            targetKind: .placeVisit
        )
        #expect(
            toVisit.save(
                entry: entry,
                places: [origin, destination],
                people: [person],
                in: context
            )
        )
        #expect(entry.kind == .placeVisit)
        #expect(entry.placeVisitDetails?.place?.id == destination.id)
        #expect(entry.transitDetails == nil)
        #expect(entry.people.map(\.id) == [person.id])
    }

    @Test("Saving a location as a place links selected snapshots without rewriting them")
    func savedPlacePromotion() throws {
        let context = try makeContext()
        let snapshot = Location(
            latitude: 45.6501,
            longitude: 25.6001,
            displayName: "Coffee Shop",
            formattedAddress: "1 Main Street, Brașov",
            timeZoneIdentifier: "Europe/Bucharest"
        )
        let entry = LogEntry(
            kind: .placeVisit,
            startTime: date("2026-07-18T10:00:00+03:00"),
            endTime: date("2026-07-18T11:00:00+03:00"),
            needsReview: false
        )
        entry.placeVisitDetails = PlaceVisitDetails(
            location: snapshot,
            placeRawText: "coffee shop"
        )
        let place = Place(
            name: "Coffee Shop",
            location: Location(
                latitude: 45.6502,
                longitude: 25.6002,
                displayName: "Coffee Shop",
                formattedAddress: "1 Main Street, Brașov",
                timeZoneIdentifier: "Europe/Bucharest"
            )
        )
        context.insert(entry)
        context.insert(place)
        try context.save()

        let matches = try SavedPlacePromotionService.matches(
            for: place,
            in: context
        )
        #expect(matches.count == 1)
        try SavedPlacePromotionService.apply(matches, to: place, in: context)

        #expect(entry.placeVisitDetails?.place?.id == place.id)
        #expect(entry.placeVisitDetails?.location == snapshot)
    }

    private func visitEntry(
        place: Place,
        start: Date?,
        end: Date?
    ) -> LogEntry {
        let entry = LogEntry(
            kind: .placeVisit,
            startTime: start,
            endTime: end,
            needsReview: start == nil || end == nil
        )
        entry.placeVisitDetails = PlaceVisitDetails(place: place)
        return entry
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
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func date(_ value: String) -> Date {
        (try? Date(value, strategy: .iso8601)) ?? .distantPast
    }
}
