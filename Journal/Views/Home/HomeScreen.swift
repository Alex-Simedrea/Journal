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

#Preview {
    @Previewable @State var selectedDay = TimelineDayKey.today()
    NavigationStack {
        HomeScreen(selectedDay: $selectedDay)
    }
}
