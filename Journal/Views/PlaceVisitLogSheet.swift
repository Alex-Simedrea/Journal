//
//  PlaceVisitLogSheet.swift
//  Journal
//

import SwiftData
import SwiftUI

struct PlaceVisitLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Place.name) private var places: [Place]
    @Query(sort: \Person.name) private var people: [Person]
    @State private var model = PlaceVisitComposerModel()

    var body: some View {
        NavigationStack {
            Form {
                PlaceVisitManualPlaceSection(model: model, places: places)
                PlaceVisitManualTimeSection(model: model)
                EntryPeopleSelectionSection(
                    people: people,
                    selectedIDs: model.selectedPeopleIDs,
                    onToggle: model.togglePerson
                )
            }
            .navigationTitle("Manual Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    PlaceVisitLogConfirmationButton(
                        model: model,
                        places: places,
                        people: people,
                        modelContext: modelContext,
                        onSaved: { dismiss() }
                    )
                }
            }
            .alert(
                "Couldn’t Log Visit",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "An unknown error occurred.")
            }
        }
        .interactiveDismissDisabled(model.isSaving)
    }
}

private struct PlaceVisitManualPlaceSection: View {
    @Bindable var model: PlaceVisitComposerModel
    let places: [Place]

    var body: some View {
        Section("Place") {
            Picker("Visited", selection: $model.placeID) {
                Text("Select a place").tag(nil as UUID?)
                ForEach(places) { place in
                    Text(place.name).tag(place.id as UUID?)
                }
            }
        }
    }
}

private struct PlaceVisitManualTimeSection: View {
    @Bindable var model: PlaceVisitComposerModel

    var body: some View {
        Section("Time") {
            DatePicker("Started", selection: $model.startTime)
            DatePicker("Ended", selection: $model.endTime, in: model.startTime...)
        }
    }
}

private struct PlaceVisitLogConfirmationButton: View {
    let model: PlaceVisitComposerModel
    let places: [Place]
    let people: [Person]
    let modelContext: ModelContext
    let onSaved: () -> Void

    var body: some View {
        Button(role: .confirm) {
            Task {
                if await model.save(
                    places: places,
                    people: people,
                    modelContext: modelContext
                ) {
                    onSaved()
                }
            }
        }
        .disabled(!model.canSave)
    }
}
