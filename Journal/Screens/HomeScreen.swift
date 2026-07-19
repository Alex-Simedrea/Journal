//
//  HomeScreen.swift
//  Journal
//

import SwiftData
import SwiftUI

struct HomeScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedDay: TimelineDayKey
    @State private var presentation = HomePresentationModel()
    @State private var isCalendarPresented = false

    private var displayedDate: Date { selectedDay.displayDate() }
    private var isToday: Bool { selectedDay == .today() }
    private var title: String {
        if isToday {
            return String(localized: "Today")
        }
        let includesYear = Calendar.current.component(.year, from: displayedDate)
            != Calendar.current.component(.year, from: .now)
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
            overviewData: presentation.overviewData,
            errorMessage: presentation.timelineErrorMessage,
            onSelect: { entryID in
                presentation.sheet = .details(entryID)
            }
        )
        .navigationTitle(title)
        .navigationSubtitle(
            isToday
                ? Text(displayedDate, format: .dateTime.month(.wide).day())
                : Text("")
        )
        .toolbarTitleDisplayMode(.large)
        .toolbar {
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
        .alert(
            "Couldn’t Prepare Timeline",
            isPresented: Binding(
                get: { presentation.setupErrorMessage != nil },
                set: { if !$0 { presentation.setupErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presentation.setupErrorMessage ?? "An unknown error occurred.")
        }
        .task {
            do {
                try TransitTypeSeeder.seedIfNeeded(in: modelContext)
            } catch {
                presentation.setupErrorMessage = error.localizedDescription
            }
        }
        .task(id: selectedDay) {
            reloadTimeline()
            await presentation.loadWorkoutRoutes(for: selectedDay)
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

private struct TimelineDateToolbar: ToolbarContent {
    let onCalendar: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: onCalendar) {
                Label("Choose date", systemImage: "calendar")
            }
        }

        ToolbarSpacer(.fixed, placement: .topBarTrailing)

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(action: onPrevious) {
                Label("Previous day", systemImage: "chevron.left")
            }

            Button(action: onNext) {
                Label("Next day", systemImage: "chevron.right")
            }
        }
    }
}

private struct TimelineCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDate: Date
    let onSelect: (TimelineDayKey) -> Void

    init(
        selectedDay: TimelineDayKey,
        onSelect: @escaping (TimelineDayKey) -> Void
    ) {
        _pendingDate = State(initialValue: selectedDay.displayDate())
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            DatePicker(
                "Date",
                selection: $pendingDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding()
            .navigationTitle("Choose Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
            .onChange(of: pendingDate) { _, newDate in
                onSelect(TimelineDayKey(date: newDate, timeZone: .current))
                dismiss()
            }
        }
    }
}

private struct HomeTimeline: View {
    let selectedDay: TimelineDayKey
    let rows: [TimelineRow]
    let unplacedOccurrences: [TimelineOccurrence]
    let overviewData: TimelineOverviewData
    let errorMessage: String?
    let onSelect: (UUID) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if overviewData.hasContent {
                    TimelineOverviewMap(data: overviewData)
                        .padding(.horizontal)
                        .padding(.bottom, 18)
                }

                if let errorMessage {
                    TimelineLoadingErrorView(message: errorMessage)
                } else if rows.isEmpty, unplacedOccurrences.isEmpty {
                    TimelineEmptyView(selectedDay: selectedDay)
                } else {
                    TimelineRulerSequence(
                        rows: rows,
                        onSelect: onSelect
                    )

                    if !unplacedOccurrences.isEmpty {
                        TimelineUnplacedSection(
                            occurrences: unplacedOccurrences,
                            onSelect: onSelect
                        )
                    }
                }
            }
            .padding(.bottom, 28)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .id(selectedDay)
    }
}

private struct TimelineEmptyView: View {
    let selectedDay: TimelineDayKey

    var body: some View {
        ContentUnavailableView {
            Label("No Entries", systemImage: "clock.arrow.circlepath")
        } description: {
            Text("There are no entries on this day.")
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding()
    }
}

private struct TimelineLoadingErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t Load Timeline", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding()
    }
}

private struct HomeDetailSheetContent: View {
    let sheet: HomeSheet
    let entryProvider: (UUID) -> LogEntry?

    var body: some View {
        VStack {
            switch sheet {
            case .details(let entryID):
                if let entry = entryProvider(entryID) {
                    EntryDetailSheet(entry: entry)
                } else {
                    ContentUnavailableView(
                        "Entry Unavailable",
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
        }
    }
}

private struct EntryDetailSheet: View {
    let entry: LogEntry

    var body: some View {
        VStack {
            switch entry.kind {
            case .transit:
                TransitDetailSheet(entry: entry)
            case .placeVisit:
                PlaceVisitDetailSheet(entry: entry)
            case .workout:
                WorkoutDetailSheet(entry: entry)
            }
        }
    }
}

#Preview {
    @Previewable @State var selectedDay = TimelineDayKey.today()
    NavigationStack {
        HomeScreen(selectedDay: $selectedDay)
    }
}
