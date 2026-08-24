import SwiftData
import SwiftUI

struct BoardingPassImportReviewSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Place.name) private var places: [Place]
    @Query(sort: \TransitType.canonicalName) private var transitTypes: [TransitType]

    let onComplete: (PendingBoardingPassImport) -> Void
    let onCancel: (PendingBoardingPassImport) -> Void

    @State private var model: BoardingPassReviewModel
    @State private var draftEntry: LogEntry?

    init(
        pendingImport: PendingBoardingPassImport,
        onComplete: @escaping (PendingBoardingPassImport) -> Void,
        onCancel: @escaping (PendingBoardingPassImport) -> Void
    ) {
        self.onComplete = onComplete
        self.onCancel = onCancel
        _model = State(
            initialValue: BoardingPassReviewModel(
                pendingImport: pendingImport
            )
        )
    }

    var body: some View {
        if let draftEntry {
            EntryDetailSheet(
                draftEntry: draftEntry,
                title: "Review Journey",
                isConfirming: model.isSaving,
                onCancel: { onCancel(model.pendingImport) },
                onConfirm: commit
            )
            .alert(
                "Couldn’t Import Journey",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "An unknown error occurred.")
            }
        } else {
            DynamicSheet {
                ProgressView("Preparing journey…")
                    .frame(maxWidth: .infinity)
                    .padding(32)
            }
            .interactiveDismissDisabled()
            .task(id: BoardingPassPreparationID(
                placeIDs: places.map(\.id),
                transitTypeNames: transitTypes.map(\.canonicalName)
            )) {
                await model.prepare(places: places, transitTypes: transitTypes)
                draftEntry = model.makeDraftEntry(places: places)
            }
        }
    }

    private func commit(
        _ entry: LogEntry,
        selectedPeopleIDs: Set<UUID>
    ) {
        Task {
            if await model.commit(
                entry,
                selectedPeopleIDs: selectedPeopleIDs,
                in: modelContext
            ) {
                onComplete(model.pendingImport)
            }
        }
    }
}

private struct BoardingPassPreparationID: Equatable {
    let placeIDs: [UUID]
    let transitTypeNames: [String]
}
