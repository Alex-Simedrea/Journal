import SwiftData
import SwiftUI

struct HomeTimeline: View {
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

struct TimelineEmptyView: View {
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

struct TimelineLoadingErrorView: View {
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
