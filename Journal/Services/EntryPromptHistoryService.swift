//
//  EntryPromptHistoryService.swift
//  Journal
//

import Foundation
import SwiftData

@MainActor
enum EntryPromptHistoryService {
    static func entries(
        around selectedDay: TimelineDayKey,
        in modelContext: ModelContext
    ) throws -> [LogEntry] {
        let lowerBound = selectedDay.addingDays(-1).conservativeQueryWindow.start
        let upperBound = selectedDay.addingDays(1).conservativeQueryWindow.end
        let predicate = #Predicate<LogEntry> { entry in
            (entry.createdAt >= lowerBound && entry.createdAt < upperBound)
                || (
                    (entry.startTime ?? upperBound) < upperBound
                        && (entry.endTime ?? lowerBound) > lowerBound
                )
                || (
                    (entry.endTime ?? upperBound) >= lowerBound
                        && (entry.endTime ?? upperBound) < upperBound
                )
        }
        return try modelContext.fetch(
            FetchDescriptor(
                predicate: predicate,
                sortBy: [
                    SortDescriptor(\LogEntry.startTime),
                    SortDescriptor(\LogEntry.createdAt),
                ]
            )
        )
    }
}
