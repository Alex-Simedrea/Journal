//
//  HomePresentationModel.swift
//  Journal
//

import Foundation
import Observation
import SwiftData

enum HomeSheet: Identifiable, Equatable {
    case transit(TransitComposerMode)
    case details(UUID)

    var id: String {
        switch self {
        case .transit(let mode):
            "transit-\(mode.rawValue)"
        case .details(let id):
            "details-\(id.uuidString)"
        }
    }
}

@MainActor
@Observable
final class HomePresentationModel {
    var sheet: HomeSheet?
    var setupErrorMessage: String?
    var timelineErrorMessage: String?
    var selectedDay = TimelineDayKey.today()
    private(set) var timelineItems: [TimelineListItem] = []
    private(set) var reviewOccurrences: [TimelineOccurrence] = []

    private var loadedEntries: [LogEntry] = []

    var hasTimelineContent: Bool {
        !timelineItems.isEmpty || !reviewOccurrences.isEmpty
    }

    func showPreviousDay() {
        selectedDay = selectedDay.addingDays(-1)
    }

    func showNextDay() {
        selectedDay = selectedDay.addingDays(1)
    }

    func showToday() {
        selectedDay = .today()
    }

    func entry(withID id: UUID) -> LogEntry? {
        loadedEntries.first { $0.id == id }
    }

    func reloadTimeline(in modelContext: ModelContext) {
        let window = selectedDay.conservativeQueryWindow
        let lowerBound = window.start
        let upperBound = window.end
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
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\LogEntry.createdAt)]
        )

        do {
            let entries = try modelContext.fetch(descriptor)
            let projection = TimelineProjection.project(
                entries: entries.map(TimelineEntrySnapshot.init),
                for: selectedDay
            )
            loadedEntries = entries
            timelineItems = projection.listItems
            reviewOccurrences = projection.reviewOccurrences
            timelineErrorMessage = nil
        } catch {
            loadedEntries = []
            timelineItems = []
            reviewOccurrences = []
            timelineErrorMessage = error.localizedDescription
        }
    }
}
