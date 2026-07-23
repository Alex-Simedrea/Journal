import SwiftData
import SwiftUI

struct TimelineDateToolbar: ToolbarContent {
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

struct TimelineCalendarSheet: View {
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

struct HomeDetailSheetContent: View {
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
