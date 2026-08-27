import Foundation
import SwiftData

nonisolated struct HomeFeedWeatherCache: Sendable {
    let summary: DayWeatherSummary
    let needsRefresh: Bool
}

nonisolated struct HomeFeedProjectionResult: Sendable {
    let snapshots: [TimelineEntrySnapshot]
    let daySummaries: [DaySummary]
    let weatherByDay: [TimelineDayKey: HomeFeedWeatherCache]
    let weatherStorageEntryByDay: [TimelineDayKey: UUID]
}

@ModelActor
actor HomeFeedProjectionStore {
    func load() throws -> HomeFeedProjectionResult {
        let entries = try modelContext.fetch(
            FetchDescriptor<LogEntry>(
                sortBy: [SortDescriptor(\LogEntry.createdAt)]
            )
        )
        let snapshots = entries.map(TimelineEntrySnapshot.init)
        let summaries = DaySummaryProjector.makeSummaries(entries: snapshots)
        let entriesByID = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.id, $0) }
        )
        var weatherByDay: [TimelineDayKey: HomeFeedWeatherCache] = [:]
        var weatherStorageEntryByDay: [TimelineDayKey: UUID] = [:]

        for summary in summaries {
            let storageEntryID = summary.occurrences.lazy
                .map(\.entryID)
                .first { entriesByID[$0] != nil }
            if let storageEntryID {
                weatherStorageEntryByDay[summary.day] = storageEntryID
            }
            guard let request = summary.weatherRequest else { continue }
            for occurrence in summary.occurrences {
                guard let entry = entriesByID[occurrence.entryID],
                      let record = entry.dayWeatherRecords.first(where: {
                          $0.matches(request)
                      }) else { continue }
                weatherByDay[summary.day] = HomeFeedWeatherCache(
                    summary: record.summary,
                    needsRefresh: record.needsRefresh
                )
                break
            }
        }

        return HomeFeedProjectionResult(
            snapshots: snapshots,
            daySummaries: summaries,
            weatherByDay: weatherByDay,
            weatherStorageEntryByDay: weatherStorageEntryByDay
        )
    }

    func persistWeather(
        _ weather: DayWeatherSummary,
        request: DayWeatherRequest,
        entryID: UUID
    ) throws {
        var descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.id == entryID }
        )
        descriptor.fetchLimit = 1
        guard let entry = try modelContext.fetch(descriptor).first else {
            return
        }
        let record = PersistedDayWeather(request: request, summary: weather)
        entry.dayWeatherRecords.removeAll {
            $0.year == record.year
                && $0.month == record.month
                && $0.day == record.day
        }
        entry.dayWeatherRecords.append(record)
        try modelContext.save()
    }
}
