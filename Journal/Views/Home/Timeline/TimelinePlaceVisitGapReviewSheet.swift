import SwiftData
import SwiftUI

struct TimelinePlaceVisitGapReviewSheet: View {
    @Environment(\.modelContext) private var modelContext

    let gapID: TimelinePlaceVisitGapID
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
                    title: "Add Place Visit",
                    isConfirming: isSaving,
                    onCancel: onCancel,
                    onConfirm: confirm
                )
            } else if let errorMessage {
                DynamicSheet {
                    ContentUnavailableView {
                        Label(
                            "Couldn’t Add Place Visit",
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
                    ProgressView("Preparing place visit…")
                        .frame(maxWidth: .infinity)
                        .padding(32)
                }
                .interactiveDismissDisabled()
                .task { await prepare() }
            }
        }
        .alert(
            "Couldn’t Add Place Visit",
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
            let entry = try TimelinePlaceVisitGapService.makeDraft(
                gapID: gapID,
                in: modelContext
            )
            entry.photoReferences =
                await PhotoAutoLinkService
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
            let entryID = try TimelinePlaceVisitGapService.insert(
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
