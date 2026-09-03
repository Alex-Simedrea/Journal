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
    private(set) var automationCandidates: [AutomationCandidateSnapshot] = []
    private(set) var overviewData = TimelineOverviewData()
    private(set) var selectedDayEntries: [LogEntry] = []
    private(set) var timelineRevision = 0

    @ObservationIgnored
    private let workoutClient: HealthKitWorkoutClient
    @ObservationIgnored
    private var loadedEntries: [LogEntry] = []
    @ObservationIgnored
    private var pendingCandidateByEntryID: [UUID: AutomationCandidateSnapshot] = [:]
    @ObservationIgnored
    private var overviewOccurrences: [TimelineOccurrence] = []
    @ObservationIgnored
    private var overviewDay: TimelineDayKey?
    @ObservationIgnored
    private var workoutRoutes: [UUID: [WorkoutCoordinateSnapshot]] = [:]

    init(workoutClient: HealthKitWorkoutClient = .shared) {
        self.workoutClient = workoutClient
    }

    var hasTimelineContent: Bool {
        !timelineItems.isEmpty
            || !reviewOccurrences.isEmpty
            || !automationCandidates.isEmpty
    }

    func entry(withID id: UUID) -> LogEntry? {
        loadedEntries.first { $0.id == id }
    }

    func pendingAutomationCandidate(
        forEntryID entryID: UUID
    ) -> AutomationCandidateSnapshot? {
        pendingCandidateByEntryID[entryID]
    }

    var pendingAutomationCandidateIDsByEntryID: [UUID: UUID] {
        pendingCandidateByEntryID.mapValues(\.id)
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
            if WorkoutTimelinePlaceReconciler.reconcile(entries: entries) {
                try modelContext.save()
            }
            let places = try modelContext.fetch(FetchDescriptor<Place>())
            let placesByID = Dictionary(
                uniqueKeysWithValues: places.map { ($0.id, $0) }
            )
            let pendingCandidates = try modelContext.fetch(
                FetchDescriptor<AutomationCandidate>(
                    sortBy: [SortDescriptor(\.startTime)]
                )
            ).compactMap {
                AutomationCandidateSnapshot($0, placesByID: placesByID)
            }
            let candidatesByID = Dictionary(
                uniqueKeysWithValues: pendingCandidates.map { ($0.id, $0) }
            )
            pendingCandidateByEntryID = Dictionary(
                uniqueKeysWithValues: entries.compactMap { entry in
                    let candidateID = entry.automationCandidateID ?? entry.id
                    guard let candidate = candidatesByID[candidateID] else {
                        return nil
                    }
                    return (entry.id, candidate)
                }
            )
            automationCandidates = pendingCandidates.filter {
                $0.day == selectedDay
            }
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
                    timelineSortTime($0) < timelineSortTime($1)
                }
            timelineItems = projection.listItems
            timelineRows = projection.rows
            reviewOccurrences = projection.reviewOccurrences
            let visibleEntryIDs = Set(projection.occurrences.map(\.entryID))
            workoutRoutes = workoutRoutes.filter {
                visibleEntryIDs.contains($0.key)
            }
            overviewData = TimelineOverviewData.make(
                occurrences: projection.occurrences,
                workoutRoutes: workoutRoutes
            )
            overviewOccurrences = projection.occurrences
            overviewDay = selectedDay
            timelineErrorMessage = nil
            timelineRevision &+= 1
        } catch {
            loadedEntries = []
            selectedDayEntries = []
            timelineItems = []
            timelineRows = []
            reviewOccurrences = []
            automationCandidates = []
            pendingCandidateByEntryID = [:]
            overviewData = TimelineOverviewData()
            overviewOccurrences = []
            overviewDay = nil
            workoutRoutes = [:]
            timelineErrorMessage = error.localizedDescription
            timelineRevision &+= 1
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

        let requestedEntryIDs = Set(requests.map(\.0))
        var routes = workoutRoutes.filter {
            requestedEntryIDs.contains($0.key)
        }
        for (entryID, workoutUUID) in requests {
            guard !Task.isCancelled else { return }
            if routes[entryID]?.count ?? 0 > 1 { continue }
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
        workoutRoutes = routes
        let updatedOverview = TimelineOverviewData.make(
            occurrences: occurrences,
            workoutRoutes: routes
        )
        if overviewData != updatedOverview {
            overviewData = updatedOverview
        }
    }

    func reloadTimeline(in modelContext: ModelContext) {
        reloadTimeline(for: .today(), in: modelContext)
    }

    private func timelineSortTime(_ entry: LogEntry) -> Date {
        entry.kind == .wakeUp
            ? entry.endTime ?? entry.startTime ?? entry.createdAt
            : entry.startTime ?? entry.endTime ?? entry.createdAt
    }
}
