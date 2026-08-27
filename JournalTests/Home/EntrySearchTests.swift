import Foundation
import Testing

@testable import Journal

@Suite("Entry search")
struct EntrySearchTests {
    private let bucharest = "Europe/Bucharest"

    @Test("Search matches people, places, and transit types")
    func supportedSearchTerms() {
        let person = TimelinePersonSnapshot(
            id: UUID(),
            name: "Alexandra",
            contactIdentifier: nil
        )
        let transit = snapshot(
            at: date("2026-08-28T10:00:00+03:00"),
            kind: .transit,
            transitType: "Métrô",
            destination: "Henri Coandă Airport",
            people: [person]
        )
        let visit = snapshot(
            at: date("2026-08-27T10:00:00+03:00"),
            kind: .placeVisit,
            visitPlace: "Piața Unirii"
        )
        let candidates = [transit, visit].map(EntrySearchCandidate.init)

        #expect(ids(matching: "alex", in: candidates) == [transit.id])
        #expect(ids(matching: "metro", in: candidates) == [transit.id])
        #expect(ids(matching: "airport", in: candidates) == [transit.id])
        #expect(ids(matching: "piata", in: candidates) == [visit.id])
    }

    @Test("Every query token can match a different entry field")
    func tokenMatchingAcrossFields() {
        let transit = snapshot(
            at: date("2026-08-28T10:00:00+03:00"),
            kind: .transit,
            transitType: "Flight",
            destination: "Henri Coandă Airport",
            people: [
                TimelinePersonSnapshot(
                    id: UUID(),
                    name: "Alexandra",
                    contactIdentifier: nil
                ),
            ]
        )
        let candidates = [EntrySearchCandidate(snapshot: transit)]

        #expect(ids(matching: "alex airport", in: candidates) == [transit.id])
        #expect(ids(matching: "alex train", in: candidates).isEmpty)
    }

    @Test("Sections are newest first and entries within a day are oldest first")
    func resultOrdering() throws {
        let olderDay = snapshot(
            at: date("2026-08-26T12:00:00+03:00"),
            kind: .placeVisit,
            visitPlace: "Library"
        )
        let newDayLate = snapshot(
            at: date("2026-08-28T18:00:00+03:00"),
            kind: .placeVisit,
            visitPlace: "Library"
        )
        let newDayEarly = snapshot(
            at: date("2026-08-28T08:00:00+03:00"),
            kind: .placeVisit,
            visitPlace: "Library"
        )

        let sections = EntrySearchIndex.sections(
            matching: "library",
            in: [olderDay, newDayLate, newDayEarly]
                .map(EntrySearchCandidate.init)
        )

        #expect(sections.map(\.day) == [day(28), day(26)])
        let latest = try #require(sections.first)
        #expect(latest.occurrences.map(\.entryID) == [
            newDayEarly.id,
            newDayLate.id,
        ])
    }

    @Test("Entries without a valid interval use their creation day")
    func unresolvedEntryDay() throws {
        let createdAt = date("2026-08-25T11:00:00+03:00")
        let snapshot = TimelineEntrySnapshot(
            createdAt: createdAt,
            startTime: nil,
            endTime: nil,
            startTimeZoneIdentifier: bucharest,
            endTimeZoneIdentifier: bucharest,
            creationTimeZoneIdentifier: bucharest,
            timeConfidence: .unresolved,
            needsReview: true,
            kind: .transit,
            transitType: "Train"
        )

        let section = try #require(
            EntrySearchIndex.sections(
                matching: "train",
                in: [EntrySearchCandidate(snapshot: snapshot)]
            ).first
        )

        #expect(section.day == day(25))
        #expect(section.occurrences.first?.role == .unresolvedReview)
    }

    private func ids(
        matching query: String,
        in candidates: [EntrySearchCandidate]
    ) -> [UUID] {
        EntrySearchIndex.sections(matching: query, in: candidates)
            .flatMap(\.occurrences)
            .map(\.entryID)
    }

    private func snapshot(
        at start: Date,
        kind: LogKind,
        transitType: String = "Transit",
        destination: String = "Destination",
        visitPlace: String = "Place",
        people: [TimelinePersonSnapshot] = []
    ) -> TimelineEntrySnapshot {
        TimelineEntrySnapshot(
            createdAt: start,
            startTime: start,
            endTime: start.addingTimeInterval(1_800),
            startTimeZoneIdentifier: bucharest,
            endTimeZoneIdentifier: bucharest,
            creationTimeZoneIdentifier: bucharest,
            timeConfidence: .explicit,
            kind: kind,
            transitType: transitType,
            destination: destination,
            visitPlace: visitPlace,
            people: people
        )
    }

    private func date(_ value: String) -> Date {
        try! Date(value, strategy: .iso8601)
    }

    private func day(_ value: Int) -> TimelineDayKey {
        TimelineDayKey(year: 2026, month: 8, day: value)
    }
}
