import SwiftData
import SwiftUI

struct TimelineTransitGapReviewSheet: View {
    @Environment(\.modelContext) private var modelContext

    let gapID: TimelineTransitGapID
    let onCancel: () -> Void
    let onComplete: (UUID) -> Void

    @State private var draftEntry: LogEntry?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let draftEntry {
                EntryDetailSheet(
                    draftEntry: draftEntry,
                    title: "Add Transit",
                    isConfirming: isSaving,
                    onCancel: onCancel,
                    onConfirm: confirm
                )
            } else if let errorMessage {
                DynamicSheet {
                    ContentUnavailableView {
                        Label(
                            "Couldn’t Add Transit",
                            systemImage: "exclamationmark.triangle"
                        )
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Close", action: onCancel)
                    }
                    .padding(24)
                }
            } else {
                DynamicSheet {
                    ProgressView("Preparing transit…")
                        .frame(maxWidth: .infinity)
                        .padding(32)
                }
                .interactiveDismissDisabled()
                .task { await prepare() }
            }
        }
        .alert(
            "Couldn’t Add Transit",
            isPresented: Binding(
                get: { draftEntry != nil && errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private func prepare() async {
        do {
            let entry = try TimelineTransitGapService.makeDraft(
                gapID: gapID,
                in: modelContext
            )
            entry.photoReferences = await PhotoAutoLinkService
                .matchingPhotoReferences(for: entry)
            guard !Task.isCancelled else { return }
            draftEntry = entry
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirm(
        _ entry: LogEntry,
        selectedPeopleIDs: Set<UUID>
    ) {
        isSaving = true
        defer { isSaving = false }
        do {
            let entryID = try TimelineTransitGapService.insert(
                entry,
                selectedPeopleIDs: selectedPeopleIDs,
                gapID: gapID,
                in: modelContext
            )
            onComplete(entryID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
