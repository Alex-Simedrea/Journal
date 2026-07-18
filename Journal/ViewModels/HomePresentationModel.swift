//
//  HomePresentationModel.swift
//  Journal
//

import Foundation
import Observation
import SwiftData

enum HomeSheet: Identifiable, Equatable {
    case describeEntry
    case manualTransit
    case manualVisit
    case details(UUID)

    var id: String {
        switch self {
        case .describeEntry:
            "describe-entry"
        case .manualTransit:
            "manual-transit"
        case .manualVisit:
            "manual-visit"
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
    private(set) var selectedDayEntries: [LogEntry] = []

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
            let selectedEntryIDs = Set(
                projection.occurrences.map(\.entryID)
                    + projection.reviewOccurrences.map(\.entryID)
            )
            loadedEntries = entries
            selectedDayEntries = entries
                .filter { selectedEntryIDs.contains($0.id) }
                .sorted {
                    ($0.startTime ?? $0.endTime ?? $0.createdAt)
                        < ($1.startTime ?? $1.endTime ?? $1.createdAt)
                }
            timelineItems = projection.listItems
            reviewOccurrences = projection.reviewOccurrences
            timelineErrorMessage = nil
        } catch {
            loadedEntries = []
            selectedDayEntries = []
            timelineItems = []
            reviewOccurrences = []
            timelineErrorMessage = error.localizedDescription
        }
    }
}
