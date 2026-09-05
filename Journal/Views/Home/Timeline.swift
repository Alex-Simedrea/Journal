import SwiftData
import SwiftUI

struct HomeTimeline: View {
    let selectedDay: TimelineDayKey
    let rows: [TimelineRow]
    let unplacedOccurrences: [TimelineOccurrence]
    let automationCandidates: [AutomationCandidateSnapshot]
    let overviewData: TimelineOverviewData
    let errorMessage: String?
    let pendingAutomationCandidateIDsByEntryID: [UUID: UUID]
    let onSelect: (UUID) -> Void
    let onSelectCandidate: (AutomationCandidateSnapshot) -> Void
    let onAcceptCandidateEntry: (UUID, UUID) -> Void
    let onDismissCandidate: (UUID) -> Void
    let onAddTransit: (TimelineTransitGapID) -> Void
    let onAddPlaceVisit: (TimelinePlaceVisitGapID) -> Void
    let onResolveBoundary: (TimelineBoundaryConflictID) -> Void

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
                } else if rows.isEmpty,
                          unplacedOccurrences.isEmpty,
                          automationCandidates.isEmpty {
                    TimelineEmptyView(selectedDay: selectedDay)
                } else {
                    if !rows.isEmpty {
                        TimelineRulerSequence(
                            rows: rows,
                            pendingAutomationCandidateIDsByEntryID:
                                pendingAutomationCandidateIDsByEntryID,
                            onSelect: onSelect,
                            onAcceptCandidateEntry: onAcceptCandidateEntry,
                            onDismissCandidate: onDismissCandidate,
                            onAddTransit: onAddTransit,
                            onAddPlaceVisit: onAddPlaceVisit,
                            onResolveBoundary: onResolveBoundary
                        )
                    }

                    if !unplacedOccurrences.isEmpty {
                        TimelineUnplacedSection(
                            occurrences: unplacedOccurrences,
                            onSelect: onSelect
                        )
                    }

                    if !automationCandidates.isEmpty {
                        TimelineAutomationCandidateSection(
                            candidates: automationCandidates,
                            onSelect: onSelectCandidate
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
