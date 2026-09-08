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

/// Read-mostly projection of the whole journal into value snapshots for the
/// home feed. Runs on its own background executor: models fetched here never
/// leave the actor, and the only write (`persistWeather`) re-fetches its
/// target by ID and saves in the same isolation without suspension points.
///
/// `DefaultSerialModelExecutor` provides mutual exclusion but no thread of
/// its own: a model-actor job awaited from the main actor would run on the
/// main thread. This actor exists to keep whole-journal fetches off the UI
/// thread, so it supplies its own serial dispatch queue as executor.
actor HomeFeedProjectionStore: ModelActor {
    nonisolated let modelExecutor: any ModelExecutor
    nonisolated let modelContainer: ModelContainer
    private nonisolated let queue: DispatchSerialQueue

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    init(modelContainer: ModelContainer) {
        queue = DispatchSerialQueue(
            label: "journal.home-feed-projection",
            qos: .userInitiated
        )
        self.modelContainer = modelContainer
        modelExecutor = DefaultSerialModelExecutor(
            modelContext: ModelContext(modelContainer)
        )
    }

#if DEBUG
    func executorUsesMainThreadForTesting() -> Bool {
        Thread.isMainThread
    }
#endif

    func load() throws -> HomeFeedProjectionResult {
        let entries = try modelContext.fetch(
            FetchDescriptor<LogEntry>(
                sortBy: [SortDescriptor(\LogEntry.createdAt)]
            )
        )
        let snapshots = entries.map(TimelineEntrySnapshot.init)
        let recordsByID = Dictionary(entries.map { ($0.id, $0.dayWeatherRecords) },
                                     uniquingKeysWith: { first, _ in first })
        return Self.project(snapshots: snapshots, recordsByID: recordsByID)
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
