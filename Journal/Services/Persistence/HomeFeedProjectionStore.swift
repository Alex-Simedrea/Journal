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

@MainActor
final class HomeFeedProjectionStore {
    // A context does not substitute for owning the container/store lifetime.
    let modelContainer: ModelContainer
    let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        modelContext = modelContainer.mainContext
    }

    func load() async throws -> HomeFeedProjectionResult {
        let entries = try modelContext.fetch(
            FetchDescriptor<LogEntry>(
                sortBy: [SortDescriptor(\LogEntry.createdAt)]
            )
        )
        let snapshots = entries.map(TimelineEntrySnapshot.init)
        let recordsByID = Dictionary(entries.map { ($0.id, $0.dayWeatherRecords) },
                                     uniquingKeysWith: { first, _ in first })
        return await Task.detached(priority: .userInitiated) {
            Self.project(snapshots: snapshots, recordsByID: recordsByID)
        }.value
    }

    nonisolated private static func project(
        snapshots: [TimelineEntrySnapshot],
        recordsByID: [UUID: [PersistedDayWeather]]
    ) -> HomeFeedProjectionResult {
        let summaries = DaySummaryProjector.makeSummaries(entries: snapshots)
        var weatherByDay: [TimelineDayKey: HomeFeedWeatherCache] = [:]
        var weatherStorageEntryByDay: [TimelineDayKey: UUID] = [:]

        for summary in summaries {
            let storageEntryID = summary.occurrences.lazy
                .map(\.entryID)
                .first { recordsByID[$0] != nil }
            if let storageEntryID {
                weatherStorageEntryByDay[summary.day] = storageEntryID
            }
            guard let request = summary.weatherRequest else { continue }
            for occurrence in summary.occurrences {
                guard let records = recordsByID[occurrence.entryID],
                      let record = records.first(where: {
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
        try JournalPersistence.save(modelContext)
    }
}
