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
            onSelect: { entryID in
                if let candidate = presentation.automationCandidates.first(
                    where: { $0.id == entryID }
                ) {
                    selectedAutomationCandidate = candidate
                } else {
                    presentation.sheet = .details(entryID)
                }
            },
            onSelectCandidate: { selectedAutomationCandidate = $0 }
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
        .sheet(item: $presentation.sheet, onDismiss: reloadTimelineAndRoutes) {
            sheet in
            HomeDetailSheetContent(
                sheet: sheet,
                entryProvider: presentation.entry(withID:)
            )
        }
        .sheet(
            item: $selectedAutomationCandidate,
            onDismiss: reloadTimelineAndRoutes
        ) { candidate in
            AutomationCandidateReviewSheet(candidateID: candidate.id) {
                selectedAutomationCandidate = nil
                reloadTimelineAndRoutes()
            }
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
            NotificationCenter.default.publisher(
                for: .automationCandidatesDidChange
            )
        ) { _ in
            reloadTimelineAndRoutes()
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
}

private struct TimelineReloadID: Equatable {
    let day: TimelineDayKey
    let contentRevision: Int
}

#Preview {
    @Previewable @State var selectedDay = TimelineDayKey.today()
    NavigationStack {
        DayTimelineScreen(selectedDay: $selectedDay)
    }
}
