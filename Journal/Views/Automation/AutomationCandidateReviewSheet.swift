import SwiftData
import SwiftUI

struct AutomationCandidateReviewSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Place.name) private var places: [Place]
    @Query private var candidates: [AutomationCandidate]
    @Query private var entries: [LogEntry]

    let candidateID: UUID
    let onComplete: () -> Void

    @State private var model = AutomationCandidateReviewModel()
    @State private var draftEntry: LogEntry?

    var body: some View {
        if let candidate, let draftEntry {
            EntryDetailSheet(
                draftEntry: draftEntry,
                title: candidate.kind == .visit
                    ? "Review Visit"
                    : "Review Transit",
                isConfirming: model.isSaving,
                onCancel: onComplete,
                onDismiss: { dismiss(candidate) },
                onConfirm: { commit($0, candidate: candidate) }
            )
            .alert(
                "Couldn’t Update Candidate",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "An unknown error occurred.")
            }
        } else if let candidate {
            DynamicSheet {
                ProgressView("Preparing candidate…")
                    .frame(maxWidth: .infinity)
                    .padding(32)
            }
            .interactiveDismissDisabled()
            .task(id: PreparationID(
                updatedAt: candidate.updatedAt,
                placeIDs: places.map(\.id),
                hasMaterializedEntry: entries.contains {
                    $0.id == candidate.id
                }
            )) {
                draftEntry = model.makeDraft(
                    candidate: candidate,
                    places: places,
                    materializedEntry: entries.first {
                        $0.id == candidate.id
                    }
                )
            }
        } else {
            ContentUnavailableView(
                "Candidate Unavailable",
                systemImage: "exclamationmark.triangle"
            )
        }
    }

    private var candidate: AutomationCandidate? {
        candidates.first { $0.id == candidateID }
    }

    private func commit(
        _ entry: LogEntry,
        candidate: AutomationCandidate
    ) {
        Task {
            if await model.commit(
                entry,
                candidate: candidate,
                in: modelContext
            ) {
                onComplete()
            }
        }
    }

    private func dismiss(_ candidate: AutomationCandidate) {
        if model.dismiss(candidate: candidate, in: modelContext) {
            onComplete()
        }
    }

}

private struct PreparationID: Equatable {
    let updatedAt: Date
    let placeIDs: [UUID]
    let hasMaterializedEntry: Bool
}
