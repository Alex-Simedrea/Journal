import Foundation
import SwiftData
import Testing

@testable import Journal

@Suite("HealthKit wake-up entries")
@MainActor
struct WakeUpTests {
    @Test("Sleep stages merge without double-counting overlaps")
    func sleepStageAggregation() throws {
        let terminalUUID = UUID()
        let samples = [
            sleepSample(start: 0, end: 60 * 60),
            sleepSample(start: 0, end: 60 * 60),
            sleepSample(
                start: 60 * 60,
                end: 70 * 60,
                isAsleep: false
            ),
            sleepSample(
                uuid: terminalUUID,
                start: 70 * 60,
                end: 120 * 60,
                timeZoneIdentifier: "Europe/Bucharest"
            ),
        ]

        let wakeUp = try #require(
            HealthKitSleepSessionBuilder.wakeUps(from: samples).first
        )

        #expect(wakeUp.sourceSampleUUID == terminalUUID)
        #expect(wakeUp.sleepStart == date(0))
        #expect(wakeUp.wakeTime == date(120 * 60))
        #expect(wakeUp.sleepDurationSeconds == 110 * 60)
        #expect(wakeUp.timeZoneIdentifier == "Europe/Bucharest")
    }

    @Test("Long interruptions create a separate wake-up")
    func separateSleepSessions() {
        let samples = [
            sleepSample(start: 0, end: 60 * 60),
            sleepSample(start: 151 * 60, end: 181 * 60),
        ]

        let wakeUps = HealthKitSleepSessionBuilder.wakeUps(from: samples)

        #expect(wakeUps.count == 2)
        #expect(wakeUps.map(\.sleepDurationSeconds) == [60 * 60, 30 * 60])
    }

    @Test("Wake-up synchronization is idempotent and mirrors HealthKit")
    func wakeUpSynchronization() throws {
        let context = try makeContext()
        let firstUUID = UUID()
        let first = HealthKitWakeUpSnapshot(
            sourceSampleUUID: firstUUID,
            sleepStart: date(0),
            wakeTime: date(8 * 60 * 60),
            sleepDurationSeconds: 7.5 * 60 * 60,
            timeZoneIdentifier: "Europe/Bucharest"
        )

        try WakeUpEntryStore.synchronize(
            snapshots: [first],
            in: context
        )
        try context.save()
        try WakeUpEntryStore.synchronize(
            snapshots: [first],
            in: context
        )
        try context.save()

        var entries = try context.fetch(FetchDescriptor<LogEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.kind == .wakeUp)
        #expect(entries.first?.wakeUpSourceSampleUUID == firstUUID)
        #expect(entries.first?.sleepDurationSeconds == 7.5 * 60 * 60)
        #expect(entries.first?.timeConfidence == .explicit)

        let replacement = HealthKitWakeUpSnapshot(
            sourceSampleUUID: UUID(),
            sleepStart: date(24 * 60 * 60),
            wakeTime: date(32 * 60 * 60),
            sleepDurationSeconds: 8 * 60 * 60,
            timeZoneIdentifier: "Europe/Bucharest"
        )
        try WakeUpEntryStore.synchronize(
            snapshots: [replacement],
            in: context
        )
        try context.save()

        entries = try context.fetch(FetchDescriptor<LogEntry>())
        #expect(entries.count == 1)
        #expect(
            entries.first?.wakeUpSourceSampleUUID
                == replacement.sourceSampleUUID
        )
    }

    @Test("Wake-ups appear only on the local wake day")
    func wakeDayProjection() throws {
        let start = try Date(
            "2026-07-17T23:00:00+03:00",
            strategy: .iso8601
        )
        let wakeTime = try Date(
            "2026-07-18T07:12:00+03:00",
            strategy: .iso8601
        )
        let snapshot = TimelineEntrySnapshot(
            createdAt: wakeTime,
            startTime: start,
            endTime: wakeTime,
            startTimeZoneIdentifier: "Europe/Bucharest",
            endTimeZoneIdentifier: "Europe/Bucharest",
            creationTimeZoneIdentifier: "Europe/Bucharest",
            timeConfidence: .explicit,
            kind: .wakeUp,
            wakeUpSleepDurationSeconds: 8 * 60 * 60 + 12 * 60
        )

        let sleepStartDay = TimelineProjection.project(
            entries: [snapshot],
            for: TimelineDayKey(year: 2026, month: 7, day: 17)
        )
        let wakeDay = TimelineProjection.project(
            entries: [snapshot],
            for: TimelineDayKey(year: 2026, month: 7, day: 18)
        )

        #expect(sleepStartDay.occurrences.isEmpty)
        #expect(wakeDay.occurrences.count == 1)
        #expect(wakeDay.occurrences.first?.role == .wakeUp)
        #expect(wakeDay.occurrences.first?.sortTime == wakeTime)
        #expect(wakeDay.occurrences.first?.visibleStartTime == wakeTime)
        #expect(wakeDay.occurrences.first?.visibleEndTime == wakeTime)
    }

    @Test("Wake-ups are history context but never model output")
    func wakeUpLLMHistory() {
        let entry = LogEntry(
            kind: .wakeUp,
            startTime: date(0),
            endTime: date(8 * 60 * 60 + 12 * 60),
            startTimeZoneIdentifier: "Europe/Bucharest",
            endTimeZoneIdentifier: "Europe/Bucharest",
            creationTimeZoneIdentifier: "Europe/Bucharest",
            timeConfidence: .explicit,
            sleepDurationSeconds: 8 * 60 * 60 + 12 * 60,
            needsReview: false
        )
        let prompt = EntryLanguageModelService.prompt(
            input: "walked to work after waking up",
            context: EntryPromptContext(
                places: [],
                people: [],
                transitTypes: [],
                visitStatisticsByPlaceID: [:],
                selectedDay: TimelineDayKey(
                    date: entry.endTime ?? .distantPast,
                    timeZone: TimeZone(identifier: "Europe/Bucharest") ?? .gmt
                ),
                selectedDayEntries: [entry],
                currentDate: date(9 * 60 * 60),
                currentLocation: Location(latitude: 45.65, longitude: 25.60)
            ),
            references: EntryPromptReferences(places: [], people: [])
        )

        #expect(prompt.contains(#""entryKind" : "wakeUp""#))
        #expect(prompt.contains(#""sleepDurationMinutes" : 492"#))
        #expect(
            EntryLanguageModelService.instructions.contains(
                "workout and wakeUp are never output entry kinds"
            )
        )
    }

    private func sleepSample(
        uuid: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        timeZoneIdentifier: String? = nil,
        isAsleep: Bool = true
    ) -> HealthKitSleepSampleSnapshot {
        HealthKitSleepSampleSnapshot(
            uuid: uuid,
            startTime: date(start),
            endTime: date(end),
            timeZoneIdentifier: timeZoneIdentifier,
            isAsleep: isAsleep
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
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
}
