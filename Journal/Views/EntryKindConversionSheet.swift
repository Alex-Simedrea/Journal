//
//  EntryKindConversionSheet.swift
//  Journal
//

import SwiftData
import SwiftUI

struct EntryKindConversionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Place.name) private var places: [Place]
    @Query(sort: \Person.name) private var people: [Person]
    @Query(sort: \TransitType.canonicalName) private var transitTypes: [TransitType]

    let entry: LogEntry
    let onConverted: () -> Void
    @State private var model: EntryKindConversionModel

    init(
        entry: LogEntry,
        targetKind: LogKind,
        onConverted: @escaping () -> Void = {}
    ) {
        self.entry = entry
        self.onConverted = onConverted
        _model = State(
            initialValue: EntryKindConversionModel(
                entry: entry,
                targetKind: targetKind
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                EntryKindConversionFields(model: model, places: places)
                EntryKindConversionTimeSection(model: model)
                EntryPeopleSelectionSection(
                    people: people,
                    selectedIDs: model.selectedPeopleIDs,
                    onToggle: model.togglePerson
                )
            }
            .navigationTitle(model.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        if model.save(
                            entry: entry,
                            places: places,
                            people: people,
                            in: modelContext
                        ) {
                            onConverted()
                            dismiss()
                        }
                    }
                    .disabled(!model.canSave)
                }
            }
            .alert(
                "Couldn’t Convert Entry",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "An unknown error occurred.")
            }
            .task(id: transitTypes.map(\.canonicalName)) {
                model.prepare(transitTypes: transitTypes)
            }
        }
    }
}

private struct EntryKindConversionFields: View {
    @Bindable var model: EntryKindConversionModel
    let places: [Place]

    var body: some View {
        if model.targetKind == .transit {
            Section("Route") {
                TextField("Transit type", text: $model.transitType)
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
        } else {
            Section("Place") {
                Picker("Visited", selection: $model.visitPlaceID) {
                    Text("Select a place").tag(nil as UUID?)
                    ForEach(places) { place in
                        Text(place.name).tag(place.id as UUID?)
                    }
                }
            }
        }
    }
}

private struct EntryKindConversionTimeSection: View {
    @Bindable var model: EntryKindConversionModel

    var body: some View {
        Section("Time") {
            DatePicker("Started", selection: $model.startTime)
            DatePicker("Ended", selection: $model.endTime, in: model.startTime...)
        }
    }
}
