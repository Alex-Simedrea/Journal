//
//  HomeScreen.swift
//  Journal
//

import SwiftData
import SwiftUI

struct HomeScreen: View {
    @Environment(\.modelContext) private var modelContext
    @State private var presentation = HomePresentationModel()

    var body: some View {
        HomeTimeline(
            selectedDay: presentation.selectedDay,
            items: presentation.timelineItems,
            reviewOccurrences: presentation.reviewOccurrences,
            errorMessage: presentation.timelineErrorMessage,
            onSelect: { entryID in
                presentation.sheet = .details(entryID)
            }
        )
        .safeAreaInset(edge: .bottom) {
            EntryLogMenu { action in
                switch action {
                case .describe:
                    presentation.sheet = .describeEntry
                case .manualTransit:
                    presentation.sheet = .manualTransit
                case .manualVisit:
                    presentation.sheet = .manualVisit
                }
            }
        }
        .toolbar {
            TimelineNavigationToolbar(
                isToday: presentation.selectedDay == .today(),
                onPrevious: presentation.showPreviousDay,
                onToday: presentation.showToday,
                onNext: presentation.showNextDay
            )
        }
        .sheet(item: $presentation.sheet, onDismiss: {
            presentation.reloadTimeline(in: modelContext)
        }) { sheet in
            HomeSheetContent(
                sheet: sheet,
                selectedDay: presentation.selectedDay,
                selectedDayEntries: presentation.selectedDayEntries,
                entryProvider: presentation.entry(withID:)
            )
        }
        .alert(
            "Couldn’t Prepare Entry Logging",
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
        .task(id: presentation.selectedDay) {
            presentation.reloadTimeline(in: modelContext)
        }
    }
}

private struct TimelineNavigationToolbar: ToolbarContent {
    let isToday: Bool
    let onPrevious: () -> Void
    let onToday: () -> Void
    let onNext: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button(action: onPrevious) {
                Label("Previous day", systemImage: "chevron.left")
            }

            Button("Today", action: onToday)
                .disabled(isToday)

            Button(action: onNext) {
                Label("Next day", systemImage: "chevron.right")
            }
        }
    }
}

private struct HomeTimeline: View {
    let selectedDay: TimelineDayKey
    let items: [TimelineListItem]
    let reviewOccurrences: [TimelineOccurrence]
    let errorMessage: String?
    let onSelect: (UUID) -> Void

    var body: some View {
        if let errorMessage {
            TimelineLoadingErrorView(message: errorMessage)
        } else if items.isEmpty, reviewOccurrences.isEmpty {
            TimelineEmptyView(selectedDay: selectedDay)
        } else {
            List {
                Section {
                    ForEach(items) { item in
                        TimelineListItemView(item: item, onSelect: onSelect)
                    }
                } header: {
                    TimelineSelectedDateHeader(day: selectedDay)
                }

                if !reviewOccurrences.isEmpty {
                    Section("Needs Review") {
                        ForEach(reviewOccurrences) { occurrence in
                            TimelineOccurrenceRow(
                                occurrence: occurrence,
                                onTap: { onSelect(occurrence.entryID) }
                            )
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct TimelineSelectedDateHeader: View {
    let day: TimelineDayKey

    var body: some View {
        Text(
            day.displayDate(),
            format: .dateTime
                .weekday(.wide)
                .month(.wide)
                .day()
                .year()
        )
        .font(.headline)
        .foregroundStyle(.primary)
        .textCase(nil)
    }
}

private struct TimelineEmptyView: View {
    let selectedDay: TimelineDayKey

    var body: some View {
        VStack(spacing: 18) {
            TimelineSelectedDateHeader(day: selectedDay)
            ContentUnavailableView {
                Label("No Entries", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("There are no entries on this day.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }
}

private struct TimelineListItemView: View {
    let item: TimelineListItem
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack {
            switch item {
            case .occurrence(let occurrence):
                TimelineOccurrenceRow(
                    occurrence: occurrence,
                    onTap: { onSelect(occurrence.entryID) }
                )
            case .timeZoneChange(let change):
                TimelineTimeZoneChangeRow(change: change)
            }
        }
    }
}

private struct TimelineOccurrenceRow: View {
    let occurrence: TimelineOccurrence
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                TimelineOccurrenceIcon(occurrence: occurrence)

                VStack(alignment: .leading, spacing: 5) {
                    TimelineOccurrenceTitle(occurrence: occurrence)

                    TimelineOccurrenceSubtitle(occurrence: occurrence)

                    TimelineOccurrenceTimeLabel(occurrence: occurrence)
                }
            }
            .contentShape(.rect)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens entry details")
    }
}

private struct TimelineOccurrenceIcon: View {
    let occurrence: TimelineOccurrence

    var body: some View {
        ZStack {
            Circle()
                .fill(.blue.opacity(0.12))
                .frame(width: 32, height: 32)
            switch occurrence.kind {
            case .placeVisit:
                PlaceSymbolImage(systemImage: occurrence.visitSystemImage)
                    .font(.title3)
            case .transit:
                Image(systemName: occurrence.role == .crossZoneArrival
                    ? "airplane.arrival"
                    : "arrow.triangle.swap")
                    .font(.title3)
                    .foregroundStyle(.blue.gradient)
            case .workout:
                Image(systemName: occurrence.workoutSystemImageName)
                    .font(.title3)
                    .foregroundStyle(.green.gradient)
            }
        }
    }
}

private struct TimelineOccurrenceSubtitle: View {
    let occurrence: TimelineOccurrence

    var body: some View {
        switch occurrence.kind {
        case .transit:
            Text("\(occurrence.origin) → \(occurrence.destination)")
                .font(.subheadline)
                .foregroundStyle(.primary)
        case .placeVisit:
            Text("Place visit")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .workout:
            WorkoutTimelineSubtitle(
                movementKind: occurrence.workoutMovementKind,
                origin: occurrence.workoutOrigin,
                destination: occurrence.workoutDestination,
                place: occurrence.workoutPlace,
                distanceMeters: occurrence.workoutDistanceMeters,
                activeEnergyKilocalories:
                    occurrence.workoutActiveEnergyKilocalories
            )
        }
    }
}

private struct WorkoutTimelineSubtitle: View {
    let movementKind: WorkoutMovementKind?
    let origin: String
    let destination: String
    let place: String
    let distanceMeters: Double?
    let activeEnergyKilocalories: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if movementKind == .moving {
                Text("\(origin) → \(destination)")
                    .foregroundStyle(.primary)
                if let distanceMeters {
                    Text(
                        Measurement(
                            value: distanceMeters,
                            unit: UnitLength.meters
                        ),
                        format: .measurement(width: .abbreviated)
                    )
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("Workout at \(place)")
                    .foregroundStyle(.secondary)
            }
            if let activeEnergyKilocalories {
                Text("\(activeEnergyKilocalories, format: .number.precision(.fractionLength(0...1))) kcal")
                .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }
}

private struct TimelineOccurrenceTitle: View {
    let occurrence: TimelineOccurrence

    var body: some View {
        HStack {
            TimelineOccurrencePrimaryTitle(occurrence: occurrence)

            if occurrence.role == .crossZoneArrival {
                Text("Arrival")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if occurrence.needsReview
                || occurrence.role == .unresolvedReview {
                Label("Review", systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct TimelineOccurrencePrimaryTitle: View {
    let occurrence: TimelineOccurrence

    var body: some View {
        switch occurrence.kind {
        case .transit:
            Text(occurrence.transitType)
                .font(.headline)
        case .placeVisit:
            Text(occurrence.visitPlace)
                .font(.headline)
        case .workout:
            Text(occurrence.workoutActivityName)
                .font(.headline)
        }
    }
}

private struct TimelineOccurrenceTimeLabel: View {
    let occurrence: TimelineOccurrence

    var body: some View {
        HStack(spacing: 5) {
            TimelineClockRange(
                startTime: occurrence.visibleStartTime,
                endTime: occurrence.visibleEndTime,
                timeZone: TimelineFormatting.timeZone(
                    identifier: occurrence.timeZoneIdentifier
                ),
                arrivalOnly: occurrence.role == .crossZoneArrival
            )

            if TimelineFormatting.differsFromDeviceTimeZone(
                occurrence.timeZoneIdentifier
            ) {
                Text(
                    TimelineFormatting.abbreviation(
                        identifier: occurrence.timeZoneIdentifier,
                        at: occurrence.sortTime
                    )
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct TimelineClockRange: View {
    let startTime: Date?
    let endTime: Date?
    let timeZone: TimeZone
    let arrivalOnly: Bool

    var body: some View {
        Group {
            if arrivalOnly, let endTime {
                Text(
                    "Arrived at \(endTime, format: .dateTime.hour().minute())"
                )
            } else if let startTime, let endTime {
                Text(
                    "\(startTime, format: .dateTime.hour().minute())–\(endTime, format: .dateTime.hour().minute())"
                )
            } else {
                Text("Time needs review")
            }
        }
        .environment(\.timeZone, timeZone)
    }
}

private struct TimelineTimeZoneChangeRow: View {
    let change: TimelineTimeZoneChange

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
            Text("Time zone changed")
            Spacer()
            Text(
                "\(TimelineFormatting.abbreviation(identifier: change.fromTimeZoneIdentifier, at: change.date)) → \(TimelineFormatting.abbreviation(identifier: change.toTimeZoneIdentifier, at: change.date))"
            )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private enum TimelineFormatting {
    static func timeZone(identifier: String) -> TimeZone {
        TimeZone(identifier: identifier) ?? .current
    }

    static func abbreviation(identifier: String, at date: Date) -> String {
        let timeZone = timeZone(identifier: identifier)
        return timeZone.abbreviation(for: date) ?? timeZone.identifier
    }

    static func differsFromDeviceTimeZone(_ identifier: String) -> Bool {
        identifier != TimeZone.current.identifier
    }
}

private enum EntryLogAction {
    case describe
    case manualTransit
    case manualVisit
}

private struct EntryLogMenu: View {
    let onSelect: (EntryLogAction) -> Void

    var body: some View {
        Menu {
            Button {
                onSelect(.describe)
            } label: {
                Label("Describe Entry", systemImage: "text.bubble")
            }

            Button {
                onSelect(.manualTransit)
            } label: {
                Label("Manual Transit", systemImage: "arrow.triangle.swap")
            }

            Button {
                onSelect(.manualVisit)
            } label: {
                Label("Manual Visit", systemImage: "mappin.and.ellipse")
            }
        } label: {
            Label("Log Entry", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.top, 8)
        .background(.bar)
    }
}

private struct HomeSheetContent: View {
    let sheet: HomeSheet
    let selectedDay: TimelineDayKey
    let selectedDayEntries: [LogEntry]
    let entryProvider: (UUID) -> LogEntry?

    var body: some View {
        switch sheet {
        case .describeEntry:
            EntryLogSheet(
                selectedDay: selectedDay,
                selectedDayEntries: selectedDayEntries
            )
        case .manualTransit:
            TransitLogSheet()
        case .manualVisit:
            PlaceVisitLogSheet()
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

private struct EntryDetailSheet: View {
    let entry: LogEntry

    var body: some View {
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

#Preview {
    HomeScreen()
}
