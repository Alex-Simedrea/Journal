//
//  TransitLogSheet.swift
//  Journal
//

import SwiftData
import SwiftUI

struct TransitLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Place.name) private var places: [Place]
    @Query(sort: \Person.name) private var people: [Person]
    @Query(sort: \TransitType.canonicalName) private var transitTypes: [TransitType]

    @State private var model = ManualTransitComposerModel()

    var body: some View {
        NavigationStack {
            Form {
                TransitManualRouteSection(
                    model: model,
                    places: places,
                    transitTypes: transitTypes
                )
                TransitManualTimeSection(model: model)
                EntryPeopleSelectionSection(
                    people: people,
                    selectedIDs: model.selectedPeopleIDs,
                    onToggle: model.togglePerson
                )
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Manual Transit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    TransitLogConfirmationButton(
                        model: model,
                        places: places,
                        people: people,
                        modelContext: modelContext,
                        onSaved: { dismiss() }
                    )
                }
            }
            .alert(
                "Couldn’t Log Transit",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "An unknown error occurred.")
            }
            .task(id: transitTypes.map(\.id)) {
                model.prepare(transitTypes: transitTypes)
            }
        }
        .interactiveDismissDisabled(model.isSaving)
    }
}

private struct TransitManualRouteSection: View {
    @Bindable var model: ManualTransitComposerModel
    let places: [Place]
    let transitTypes: [TransitType]

    var body: some View {
        Section("Route") {
            Picker("Type", selection: $model.transitType) {
                ForEach(transitTypes) { type in
                    Text(type.canonicalName).tag(type.canonicalName)
                }
            }

            Picker("From", selection: $model.originPlaceID) {
                Text("Select a place").tag(nil as UUID?)
                ForEach(places) { place in
                    Text(place.name).tag(place.id as UUID?)
                }
            }

            Picker("To", selection: $model.destinationPlaceID) {
                Text("Select a place").tag(nil as UUID?)
                ForEach(places) { place in
                    Text(place.name).tag(place.id as UUID?)
                }
            }
        }
    }
}

private struct TransitManualTimeSection: View {
    @Bindable var model: ManualTransitComposerModel

    var body: some View {
        Section("Time") {
            DatePicker("Started", selection: $model.startTime)
            DatePicker("Ended", selection: $model.endTime, in: model.startTime...)
        }
    }
}

private struct TransitLogConfirmationButton: View {
    let model: ManualTransitComposerModel
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
