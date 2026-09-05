import SwiftData
import SwiftUI

struct DayTimelineScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedDay: TimelineDayKey
    @State private var presentation = HomePresentationModel()
    @State private var isCalendarPresented = false
    @State private var selectedAutomationCandidate:
        AutomationCandidateSnapshot?
    @State private var pendingEntryDeletionID: UUID?
    @State private var pendingCandidateDismissalID: UUID?
    @State private var selectedTransitGap: TimelineTransitGapSelection?
    @State private var selectedPlaceVisitGap: TimelinePlaceVisitGapID?
    @State private var selectedBoundaryConflict: TimelineBoundaryConflictID?
    var showsCloseButton = true
    var contentRevision = 0

    private var displayedDate: Date { selectedDay.displayDate() }
    private var isToday: Bool { selectedDay == .today() }

    private var title: String {
        if isToday {
            return String(localized: "Today")
        }
        let includesYear = Calendar.current.component(
            .year,
            from: displayedDate
        ) != Calendar.current.component(.year, from: .now)
        return includesYear
            ? displayedDate.formatted(
                .dateTime.weekday(.wide).month(.wide).day().year()
            )
            : displayedDate.formatted(
                .dateTime.weekday(.wide).month(.wide).day()
            )
    }

    var body: some View {
        HomeTimeline(
            selectedDay: selectedDay,
            rows: presentation.timelineRows,
            unplacedOccurrences: presentation.reviewOccurrences,
            automationCandidates: presentation.automationCandidates,
            overviewData: presentation.overviewData,
            errorMessage: presentation.timelineErrorMessage,
            pendingAutomationCandidateIDsByEntryID:
                presentation.pendingAutomationCandidateIDsByEntryID,
            onSelect: { entryID in
                if let candidate = presentation.pendingAutomationCandidate(
                    forEntryID: entryID
                ) {
                    selectedAutomationCandidate = candidate
                } else {
                    presentation.sheet = .details(entryID)
                }
            },
            onSelectCandidate: { selectedAutomationCandidate = $0 },
            onAcceptCandidateEntry: acceptCandidateEntry,
            onDismissCandidate: dismissCandidate,
            onAddTransit: addTransit,
            onAddPlaceVisit: { selectedPlaceVisitGap = $0 },
            onResolveBoundary: { selectedBoundaryConflict = $0 }
        )
        .navigationTitle(title)
        .navigationSubtitle(
            isToday
                ? Text(displayedDate, format: .dateTime.month(.wide).day())
                : Text("")
        )
        .toolbarTitleDisplayMode(.large)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
            }

            TimelineDateToolbar(
                onCalendar: { isCalendarPresented = true },
                onPrevious: {
                    selectedDay = selectedDay.addingDays(-1)
                },
                onNext: {
                    selectedDay = selectedDay.addingDays(1)
                }
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HomeEntryComposer(
                selectedDay: selectedDay,
                timelineRevision: presentation.timelineRevision,
                onEntryChanged: reloadTimelineAndRoutes
            )
        }
        .sheet(isPresented: $isCalendarPresented) {
            TimelineCalendarSheet(
                selectedDay: selectedDay,
                onSelect: {
                    selectedDay = $0
                    isCalendarPresented = false
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(item: $presentation.sheet, onDismiss: finishEntrySheet) {
            sheet in
            HomeDetailSheetContent(
                sheet: sheet,
                entryProvider: presentation.entry(withID:),
                onRequestDelete: requestEntryDeletion
            )
        }
        .sheet(
            item: $selectedAutomationCandidate,
            onDismiss: finishCandidateSheet
        ) { candidate in
            AutomationCandidateReviewSheet(
                candidateID: candidate.id,
                onComplete: { selectedAutomationCandidate = nil },
                onRequestDismiss: requestCandidateDismissal
            )
        }
        .sheet(item: $selectedTransitGap) { selection in
            TimelineTransitGapReviewSheet(
                gapID: selection.gapID,
                onCancel: { selectedTransitGap = nil },
                onComplete: finishAddingTransit
            )
        }
        .sheet(item: $selectedPlaceVisitGap) { gapID in
            TimelinePlaceVisitGapReviewSheet(
                gapID: gapID,
                onCancel: { selectedPlaceVisitGap = nil },
                onComplete: finishAddingPlaceVisit
            )
        }
        .sheet(item: $selectedBoundaryConflict) { conflictID in
            TimelineBoundaryResolutionSheet(
                conflictID: conflictID,
                onCancel: { selectedBoundaryConflict = nil },
                onComplete: {
                    selectedBoundaryConflict = nil
                    reloadTimelineAndRoutes()
                }
            )
        }
        .alert(
            "Couldn’t Prepare Timeline",
            isPresented: Binding(
                get: { presentation.setupErrorMessage != nil },
                set: { if !$0 { presentation.setupErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                presentation.setupErrorMessage
                    ?? "An unknown error occurred."
            )
        }
        .task {
            do {
                try TransitTypeSeeder.seedIfNeeded(in: modelContext)
            } catch {
                presentation.setupErrorMessage = error.localizedDescription
            }
        }
        .task(id: TimelineReloadID(
            day: selectedDay,
            contentRevision: contentRevision
        )) {
            reloadTimeline()
            await presentation.loadWorkoutRoutes(for: selectedDay)
        }
        .onReceive(
            TimelineDataChange.publisher
        ) { change in
            switch change {
            case .enrichment:
                reloadTimeline()
            case .structure:
                reloadTimelineAndRoutes()
            }
        }
    }

    private func reloadTimeline() {
        presentation.reloadTimeline(for: selectedDay, in: modelContext)
    }

    private func reloadTimelineAndRoutes() {
        reloadTimeline()
        Task {
            await presentation.loadWorkoutRoutes(for: selectedDay)
        }
    }

    private func requestEntryDeletion(_ entryID: UUID) {
        pendingEntryDeletionID = entryID
        presentation.sheet = nil
    }

    private func finishEntrySheet() {
        if let entryID = pendingEntryDeletionID {
            pendingEntryDeletionID = nil
            do {
                try JournalDeletionService.delete(
                    entryID: entryID,
                    in: modelContext
                )
            } catch {
                presentation.setupErrorMessage = error.localizedDescription
            }
        }
        reloadTimelineAndRoutes()
    }

    private func requestCandidateDismissal(_ candidateID: UUID) {
        pendingCandidateDismissalID = candidateID
        selectedAutomationCandidate = nil
    }

    private func acceptCandidateEntry(
        _ entryID: UUID,
        _ candidateID: UUID
    ) {
        do {
            guard let acceptedEntryID = try AutomationCandidateStore
                .acceptMaterializedTransit(
                    candidateID: candidateID,
                    entryID: entryID,
                    in: modelContext
                ) else {
                reloadTimelineAndRoutes()
                return
            }
            enrichAcceptedTransit(entryID: acceptedEntryID)
        } catch {
            presentation.setupErrorMessage = error.localizedDescription
        }
    }

    private func dismissCandidate(_ candidateID: UUID) {
        do {
            try AutomationCandidateStore.dismiss(
                candidateID: candidateID,
                in: modelContext
            )
        } catch {
            presentation.setupErrorMessage = error.localizedDescription
        }
    }

    private func enrichAcceptedTransit(entryID: UUID) {
        let container = modelContext.container
        Task {
            let enrichmentContext = ModelContext(container)
            enrichmentContext.autosaveEnabled = false
            _ = try? await EntryWeatherService.populate(
                entryID: entryID,
                in: enrichmentContext
            )
            await TransitDistanceService.populate(
                entryID: entryID,
                in: enrichmentContext
            )
            try? await PhotoAutoLinkService.synchronize(
                in: enrichmentContext
            )
        }
    }

    private func addTransit(_ gapID: TimelineTransitGapID) {
        selectedTransitGap = TimelineTransitGapSelection(gapID: gapID)
    }

    private func finishAddingTransit(_ entryID: UUID) {
        selectedTransitGap = nil
        reloadTimelineAndRoutes()
        enrichGapTransit(entryID: entryID)
    }

    private func finishAddingPlaceVisit(_ entryID: UUID) {
        selectedPlaceVisitGap = nil
        reloadTimelineAndRoutes()
        let container = modelContext.container
        Task {
            let enrichmentContext = ModelContext(container)
            enrichmentContext.autosaveEnabled = false
            _ = try? await EntryWeatherService.populate(
                entryID: entryID,
                in: enrichmentContext
            )
            try? await PhotoAutoLinkService.synchronize(in: enrichmentContext)
        }
    }

    private func enrichGapTransit(entryID: UUID) {
        let container = modelContext.container
        Task {
            let enrichmentContext = ModelContext(container)
            enrichmentContext.autosaveEnabled = false
            await TransitDistanceService.populate(
                entryID: entryID,
                in: enrichmentContext
            )
            try? await PhotoAutoLinkService.synchronize(
                in: enrichmentContext
            )
        }
    }

    private func finishCandidateSheet() {
        if let candidateID = pendingCandidateDismissalID {
            pendingCandidateDismissalID = nil
            do {
                try AutomationCandidateStore.dismiss(
                    candidateID: candidateID,
                    in: modelContext
                )
            } catch {
                presentation.setupErrorMessage = error.localizedDescription
            }
        }
        reloadTimelineAndRoutes()
    }
}

private struct TimelineReloadID: Equatable {
    let day: TimelineDayKey
    let contentRevision: Int
}

private struct TimelineTransitGapSelection: Identifiable {
    let gapID: TimelineTransitGapID

    var id: TimelineTransitGapID { gapID }
}

#Preview {
    @Previewable @State var selectedDay = TimelineDayKey.today()
    NavigationStack {
        DayTimelineScreen(selectedDay: $selectedDay)
    }
}
