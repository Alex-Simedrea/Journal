import Foundation
import SwiftData
import Testing

@testable import Journal

@Suite("Timeline projection")
@MainActor
struct TimelineProjectionTests {
    private let bucharest = "Europe/Bucharest"
    private let newYork = "America/New_York"

    @Test("The conservative SwiftData query supports optional entry times")
    func conservativeSwiftDataQuery() throws {
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
        let context = ModelContext(container)
        context.insert(
            LogEntry(
                kind: .transit,
                creationTimeZoneIdentifier: bucharest,
                needsReview: true
            )
        )
        try context.save()

        let presentation = HomePresentationModel()
        presentation.reloadTimeline(in: context)

        #expect(presentation.timelineErrorMessage == nil)
        #expect(presentation.reviewOccurrences.count == 1)
    }

    @Test("Same-zone intervals appear on every overlapping day")
    func sameAndMultipleDayIntervals() {
        let sameDay = entry(
            createdAt: date("2026-07-17T09:00:00+03:00"),
            start: date("2026-07-17T10:00:00+03:00"),
            end: date("2026-07-17T11:00:00+03:00")
        )
        let multipleDays = entry(
            createdAt: date("2026-07-17T09:00:00+03:00"),
            start: date("2026-07-17T22:00:00+03:00"),
            end: date("2026-07-19T02:00:00+03:00")
        )

        let july17 = project([sameDay, multipleDays], on: day(17))
        let july18 = project([sameDay, multipleDays], on: day(18))
        let july19 = project([sameDay, multipleDays], on: day(19))

        #expect(july17.occurrences.count == 2)
        #expect(july18.occurrences.map(\.entryID) == [multipleDays.id])
        #expect(july19.occurrences.map(\.entryID) == [multipleDays.id])
    }

    @Test("An interval ending at midnight does not occupy the next day")
    func endingAtMidnight() {
        let snapshot = entry(
            createdAt: date("2026-07-17T20:00:00+03:00"),
            start: date("2026-07-17T22:00:00+03:00"),
            end: date("2026-07-18T00:00:00+03:00")
        )

        #expect(project([snapshot], on: day(17)).occurrences.count == 1)
        #expect(project([snapshot], on: day(18)).occurrences.isEmpty)
    }

    @Test("Gregorian day intervals respect 23 and 25 hour DST days")
    func daylightSavingDayLengths() throws {
        let zone = try #require(TimeZone(identifier: bucharest))
        let springDay = TimelineDayKey(year: 2026, month: 3, day: 29)
        let autumnDay = TimelineDayKey(year: 2026, month: 10, day: 25)
        let springDuration = try #require(
            springDay.dateInterval(in: zone)?.duration
        )
        let autumnDuration = try #require(
            autumnDay.dateInterval(in: zone)?.duration
        )

        #expect(springDuration == TimeInterval(23 * 60 * 60))
        #expect(autumnDuration == TimeInterval(25 * 60 * 60))

        let springEntry = entry(
            createdAt: date("2026-03-28T20:00:00+02:00"),
            start: date("2026-03-28T23:00:00+02:00"),
            end: date("2026-03-30T01:00:00+03:00")
        )
        #expect(
            project([springEntry], on: springDay).occurrences.count == 1
        )
    }

    @Test("Cross-zone transit is coalesced to one card per day")
    func bucharestToNewYork() {
        let flight = entry(
            createdAt: date("2026-07-17T20:00:00+03:00"),
            start: date("2026-07-17T22:00:00+03:00"),
            end: date("2026-07-18T01:00:00-04:00"),
            endZone: newYork
        )

        let departureDay = project([flight], on: day(17))
        let arrivalDay = project([flight], on: day(18))

        #expect(departureDay.occurrences.map(\.role) == [.intervalDay])
        #expect(arrivalDay.occurrences.map(\.role) == [.intervalDay])
        #expect(arrivalDay.occurrences.first?.changesTimeZone == true)
        #expect(
            arrivalDay.occurrences.first?.endTimeZoneIdentifier == newYork
        )
    }

    @Test("Absolute ordering survives a local clock moving backward")
    func backwardLocalClockAfterZoneChange() throws {
        let flight = entry(
            createdAt: date("2026-07-17T17:00:00+03:00"),
            start: date("2026-07-17T18:00:00+03:00"),
            end: date("2026-07-17T14:00:00-04:00"),
            endZone: newYork
        )
        let result = project([flight], on: day(17))

        #expect(result.occurrences.map(\.role) == [.intervalDay])
        #expect(result.listItems.count == 1)
        #expect(result.occurrences.first?.changesTimeZone == true)

        let startZone = try #require(TimeZone(identifier: bucharest))
        let endZone = try #require(TimeZone(identifier: newYork))
        let startHour = hour(of: flight.startTime, in: startZone)
        let endHour = hour(of: flight.endTime, in: endZone)
        #expect(endHour < startHour)
    }

    @Test("Stored event zones are independent of the device zone")
    func storedZonesRemainStable() {
        let snapshot = entry(
            createdAt: date("2026-07-17T17:00:00+03:00"),
            start: date("2026-07-17T18:00:00+03:00"),
            end: date("2026-07-17T14:00:00-04:00"),
            endZone: newYork
        )

        let result = project([snapshot], on: day(17))
        #expect(result.occurrences.first?.timeZoneIdentifier == bucharest)
        #expect(result.occurrences.first?.endTimeZoneIdentifier == newYork)
    }

    @Test("Rows distinguish contiguous, gapped, and overlapping entries")
    func rowRelationships() {
        let first = entry(
            createdAt: date("2026-07-17T08:00:00+03:00"),
            start: date("2026-07-17T09:00:00+03:00"),
            end: date("2026-07-17T10:00:00+03:00")
        )
        let contiguous = entry(
            createdAt: date("2026-07-17T08:00:00+03:00"),
            start: date("2026-07-17T10:00:00+03:00"),
            end: date("2026-07-17T11:00:00+03:00")
        )
        let overlapping = entry(
            createdAt: date("2026-07-17T08:00:00+03:00"),
            start: date("2026-07-17T10:30:00+03:00"),
            end: date("2026-07-17T11:30:00+03:00")
        )
        let gapped = entry(
            createdAt: date("2026-07-17T08:00:00+03:00"),
            start: date("2026-07-17T12:00:00+03:00"),
            end: date("2026-07-17T13:00:00+03:00")
        )

        let rows = project(
            [first, contiguous, overlapping, gapped],
            on: day(17)
        ).rows

        #expect(rows[0].relationshipToPrevious == .first)
        #expect(rows[1].relationshipToPrevious == .contiguous)
        #expect(rows[2].relationshipToPrevious == .overlap)
        #expect(
            rows[3].relationshipToPrevious == .gap(30 * 60)
        )
    }

    @Test("All boundaries match within the displayed minute")
    func minuteBoundaryMatching() {
        let previous = entry(
            createdAt: date("2026-07-17T08:00:00+03:00"),
            start: date("2026-07-17T09:00:00+03:00"),
            end: date("2026-07-17T10:00:05+03:00")
        )
        let regularEntry = entry(
            createdAt: date("2026-07-17T08:00:00+03:00"),
            start: date("2026-07-17T10:00:52+03:00"),
            end: date("2026-07-17T11:00:00+03:00")
        )

        let regularRows = project([previous, regularEntry], on: day(17)).rows

        #expect(regularRows[1].relationshipToPrevious == .contiguous)
    }

    @Test("Missing, start-only, and end-only entries are grouped for review")
    func incompleteTimesNeedReview() {
        let createdAt = date("2026-07-17T12:00:00+03:00")
        let missing = entry(createdAt: createdAt, start: nil, end: nil)
        let startOnly = entry(
            createdAt: createdAt,
            start: date("2026-07-17T13:00:00+03:00"),
            end: nil
        )
        let endOnly = entry(
            createdAt: createdAt,
            start: nil,
            end: date("2026-07-17T14:00:00+03:00")
        )

        let result = project([missing, startOnly, endOnly], on: day(17))
        #expect(result.occurrences.isEmpty)
        #expect(result.reviewOccurrences.count == 3)
        #expect(
            result.reviewOccurrences.allSatisfy {
                $0.role == .unresolvedReview
            }
        )
    }

    @Test("Editing and deleting entries changes every derived occurrence")
    func editingAndDeleting() {
        let original = entry(
            createdAt: date("2026-07-17T08:00:00+03:00"),
            start: date("2026-07-17T23:00:00+03:00"),
            end: date("2026-07-18T02:00:00+03:00")
        )
        let selectedDay = day(18)
        #expect(project([original], on: selectedDay).occurrences.count == 1)

        let edited = TimelineEntrySnapshot(
            id: original.id,
            createdAt: original.createdAt,
            startTime: date("2026-07-17T20:00:00+03:00"),
            endTime: date("2026-07-17T21:00:00+03:00"),
            startTimeZoneIdentifier: bucharest,
            endTimeZoneIdentifier: bucharest,
            creationTimeZoneIdentifier: bucharest,
            timeConfidence: .manualOverride
        )
        #expect(project([edited], on: selectedDay).occurrences.isEmpty)
        #expect(project([], on: selectedDay).occurrences.isEmpty)
    }

    private func project(
        _ entries: [TimelineEntrySnapshot],
        on day: TimelineDayKey
    ) -> TimelineProjection {
        TimelineProjection.project(entries: entries, for: day)
    }

    private func entry(
        createdAt: Date,
        start: Date?,
        end: Date?,
        startZone: String? = nil,
        endZone: String? = nil
    ) -> TimelineEntrySnapshot {
        TimelineEntrySnapshot(
            createdAt: createdAt,
            startTime: start,
            endTime: end,
            startTimeZoneIdentifier: startZone ?? bucharest,
            endTimeZoneIdentifier: endZone ?? bucharest,
            creationTimeZoneIdentifier: bucharest,
            timeConfidence: start != nil && end != nil ? .explicit : .unresolved,
            needsReview: start == nil || end == nil
        )
    }

    private func day(_ value: Int) -> TimelineDayKey {
        TimelineDayKey(year: 2026, month: 7, day: value)
    }

    private func date(_ value: String) -> Date {
        do {
            return try Date(value, strategy: .iso8601)
        } catch {
            Issue.record("Could not parse test date: \(value)")
            return .distantPast
        }
    }

    private func hour(of date: Date?, in timeZone: TimeZone) -> Int {
        guard let date else { return -1 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: date)
    }
}
