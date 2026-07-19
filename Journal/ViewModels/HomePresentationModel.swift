//
//  HomePresentationModel.swift
//  Journal
//

import Foundation
import Observation
import SwiftData

enum HomeSheet: Identifiable, Equatable {
    case details(UUID)

    var id: String {
        switch self {
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
    private(set) var timelineItems: [TimelineListItem] = []
    private(set) var timelineRows: [TimelineRow] = []
    private(set) var reviewOccurrences: [TimelineOccurrence] = []
    private(set) var overviewData = TimelineOverviewData()
    private(set) var selectedDayEntries: [LogEntry] = []

    @ObservationIgnored
    private let workoutClient: HealthKitWorkoutClient
    @ObservationIgnored
    private var loadedEntries: [LogEntry] = []
    @ObservationIgnored
    private var overviewOccurrences: [TimelineOccurrence] = []
    @ObservationIgnored
    private var overviewDay: TimelineDayKey?

    init(workoutClient: HealthKitWorkoutClient = .shared) {
        self.workoutClient = workoutClient
    }

    var hasTimelineContent: Bool {
        !timelineItems.isEmpty || !reviewOccurrences.isEmpty
    }

    func entry(withID id: UUID) -> LogEntry? {
        loadedEntries.first { $0.id == id }
    }

    func reloadTimeline(
        for selectedDay: TimelineDayKey,
        in modelContext: ModelContext
    ) {
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
            timelineRows = projection.rows
            reviewOccurrences = projection.reviewOccurrences
            overviewData = TimelineOverviewData.make(
                occurrences: projection.occurrences
            )
            overviewOccurrences = projection.occurrences
            overviewDay = selectedDay
            timelineErrorMessage = nil
        } catch {
            loadedEntries = []
            selectedDayEntries = []
            timelineItems = []
            timelineRows = []
            reviewOccurrences = []
            overviewData = TimelineOverviewData()
            overviewOccurrences = []
            overviewDay = nil
            timelineErrorMessage = error.localizedDescription
        }
    }

    func loadWorkoutRoutes(for selectedDay: TimelineDayKey) async {
        let occurrences = overviewOccurrences
        let requests = occurrences.compactMap { occurrence -> (UUID, UUID)? in
            guard occurrence.snapshot.workoutMovementKind == .moving,
                  let workoutUUID = occurrence.snapshot.workoutUUID else {
                return nil
            }
            return (occurrence.entryID, workoutUUID)
        }
        guard !requests.isEmpty else { return }

        var routes: [UUID: [WorkoutCoordinateSnapshot]] = [:]
        for (entryID, workoutUUID) in requests {
            guard !Task.isCancelled else { return }
            do {
                let points = try await workoutClient.exactRoute(
                    for: workoutUUID
                )
                if points.count > 1 {
                    routes[entryID] = points
                }
            } catch is CancellationError {
                return
            } catch {
                print("HealthKit overview route lookup failed: \(error)")
            }
        }

        guard !Task.isCancelled,
              overviewDay == selectedDay,
              overviewOccurrences.map(\.id) == occurrences.map(\.id) else {
            return
        }
        overviewData = TimelineOverviewData.make(
            occurrences: occurrences,
            workoutRoutes: routes
        )
    }

    func reloadTimeline(in modelContext: ModelContext) {
        reloadTimeline(for: .today(), in: modelContext)
    }
}
