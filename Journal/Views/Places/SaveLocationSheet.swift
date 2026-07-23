//
//  SaveLocationAsPlaceSheet.swift
//  Journal
//

import SwiftData
import SwiftUI

struct SaveLocationAsPlaceRequest: Identifiable {
    let id = UUID()
    let name: String
    let location: Location
}

struct EntryLocationSaveOption: Identifiable {
    let id: String
    let label: LocalizedStringResource
    let name: String
    let location: Location
    let isAlreadySaved: Bool
}

struct EntrySavedPlaceActionsSection: View {
    let options: [EntryLocationSaveOption]
    let onSelect: (EntryLocationSaveOption) -> Void

    var body: some View {
        let unsavedOptions = options.filter { !$0.isAlreadySaved }
        if !unsavedOptions.isEmpty {
            Section("Saved Places") {
                ForEach(unsavedOptions) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        Label(option.label, systemImage: "bookmark")
                    }
                }
            }
        }
    }
}

struct SaveLocationAsPlaceSheet: View {
    let request: SaveLocationAsPlaceRequest

    @State private var savedPlace: Place?

    var body: some View {
        if let savedPlace {
            SavedPlaceBackfillSheet(place: savedPlace)
        } else {
            SaveLocationPlaceEditorStep(
                request: request,
                onSave: { savedPlace = $0 }
            )
        }
    }
}

private struct SaveLocationPlaceEditorStep: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let request: SaveLocationAsPlaceRequest
    let onSave: (Place) -> Void

    @State private var model: PlaceEditorModel

    init(
        request: SaveLocationAsPlaceRequest,
        onSave: @escaping (Place) -> Void
    ) {
        self.request = request
        self.onSave = onSave
        _model = State(
            initialValue: PlaceEditorModel(
                initialName: request.name,
                initialLocation: request.location,
                allowsCurrentLocationCapture: false
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                PlaceEditorDetailsSection(model: model)
                PlaceEditorLocationSection(model: model)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Save as Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        if let place = model.insertPlace(in: modelContext) {
                            onSave(place)
                        }
                    }
                    .disabled(!model.canSave)
                }
            }
        }
        .onDisappear { model.stop() }
    }
}

private struct SavedPlaceBackfillSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let place: Place

    @State private var matches: [EntryLocationAssociationMatch] = []
    @State private var selectedMatchIDs: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                SavedPlaceBackfillExplanation(placeName: place.name)
                SavedPlaceBackfillMatches(
                    matches: matches,
                    selectedMatchIDs: $selectedMatchIDs
                )
            }
            .navigationTitle("Link Past Entries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { apply() }
                }
            }
            .task { loadMatches() }
            .alert(
                "Couldn’t Link Entries",
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
    }

    private func loadMatches() {
        do {
            matches = try SavedPlacePromotionService.matches(
                for: place,
                in: modelContext
            )
            selectedMatchIDs = Set(matches.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply() {
        do {
            try SavedPlacePromotionService.apply(
                matches.filter { selectedMatchIDs.contains($0.id) },
                to: place,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SavedPlaceBackfillExplanation: View {
    let placeName: String

    var body: some View {
        Section {
            Text("Choose which matching historical locations should link to \(placeName). Their original location snapshots will remain unchanged.")
        }
    }
}

private struct SavedPlaceBackfillMatches: View {
    let matches: [EntryLocationAssociationMatch]
    @Binding var selectedMatchIDs: Set<String>

    var body: some View {
        Section("Matching Entries") {
            if matches.isEmpty {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "link",
                    description: Text("The place was saved without changing past entries.")
                )
            } else {
                ForEach(matches) { match in
                    SavedPlaceBackfillMatchButton(
                        match: match,
                        isSelected: selectedMatchIDs.contains(match.id)
                    ) {
                        if selectedMatchIDs.contains(match.id) {
                            selectedMatchIDs.remove(match.id)
                        } else {
                            selectedMatchIDs.insert(match.id)
                        }
                    }
                }
            }
        }
    }
}

private struct SavedPlaceBackfillMatchButton: View {
    let match: EntryLocationAssociationMatch
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(match.slot.title)
                        .foregroundStyle(.primary)
                    Text(match.entry.startTime ?? match.entry.createdAt, format: .dateTime.day().month().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            }
        }
    }
}
