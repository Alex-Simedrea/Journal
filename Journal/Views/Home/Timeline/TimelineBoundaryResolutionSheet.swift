import SwiftData
import SwiftUI

struct TimelineBoundaryResolutionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [LogEntry]

    let conflictID: TimelineBoundaryConflictID
    let onCancel: () -> Void
    let onComplete: () -> Void

    @State private var placeSource: EntryLinkValueSource = .current
    @State private var errorMessage: String?
    @State private var chromeHeight: CGFloat = 0

    var body: some View {
        DynamicSheet {
            DynamicSheetNavigationContainer(
                route: conflictID,
                movesForward: true,
                title: "Resolve Location",
                isScrolled: false,
                chromeHeight: $chromeHeight
            ) {
                Group {
                    if let previous, let next {
                        EntryLinkResolutionEditor(
                            entry: previous,
                            neighbor: next,
                            timeSource: .constant(.current),
                            placeSource: $placeSource,
                            includesTime: false
                        )
                    } else {
                        ContentUnavailableView(
                            "Entries Unavailable",
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, chromeHeight + 8)
                .padding(.bottom, 18)
            } leading: {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Close")
            } trailing: {
                Button(action: confirm) {
                    Image(systemName: "checkmark")
                        .font(.title2)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(.blue)
                .disabled(previous == nil || next == nil)
                .accessibilityLabel("Resolve Location")
            } accessory: {
                EmptyView()
            }
        }
        .alert(
            "Couldn’t Resolve Location",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private var previous: LogEntry? {
        entries.first { $0.id == conflictID.previousEntryID }
    }

    private var next: LogEntry? {
        entries.first { $0.id == conflictID.nextEntryID }
    }

    private func confirm() {
        guard let previous, let next else { return }
        do {
            let transitIDs = try EntryLinkingService.link(
                previous,
                to: next,
                alignment: EntryLinkAlignment(
                    timeSource: .current,
                    placeSource: placeSource
                ),
                in: modelContext
            )
            refreshTransitDistances(for: transitIDs)
            TimelineDataChange.post(.structure)
            onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshTransitDistances(for entryIDs: Set<UUID>) {
        for entry in entries where entryIDs.contains(entry.id) {
            TransitDistanceService.refreshInBackground(
                entry,
                in: modelContext
            )
        }
    }
}
