//
//  PlaceVisitEditSheet.swift
//  Journal
//

import SwiftData
import SwiftUI

struct PlaceVisitEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Place.name) private var places: [Place]
    @Query(sort: \Person.name) private var people: [Person]

    let entry: LogEntry
    @State private var model: PlaceVisitEditModel
    @State private var isPresentingLocationPicker = false

    init(entry: LogEntry) {
        self.entry = entry
        _model = State(initialValue: PlaceVisitEditModel(entry: entry))
    }

    var body: some View {
        NavigationStack {
            Form {
                PlaceVisitEditPlaceSection(
                    model: model,
                    places: places,
                    onChooseLocation: { isPresentingLocationPicker = true }
                )
                PlaceVisitEditTimeSection(model: model)
                EntryPeopleSelectionSection(
                    people: people,
                    selectedIDs: model.selectedPeopleIDs,
                    onToggle: model.togglePerson
                )
            }
            .navigationTitle("Edit Visit")
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
                            dismiss()
                        }
                    }
                    .disabled(!model.canSave)
                }
            }
            .alert(
                "Couldn’t Save Visit",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "An unknown error occurred.")
            }
            .sheet(isPresented: $isPresentingLocationPicker) {
                EntryLocationPickerSheet(
                    title: "Choose Location",
                    places: places,
                    onSelect: model.selectLocation
                )
            }
        }
    }
}

private struct PlaceVisitEditPlaceSection: View {
    @Bindable var model: PlaceVisitEditModel
    let places: [Place]
    let onChooseLocation: () -> Void

    var body: some View {
        Section("Place") {
            EntryLocationSelectionButton(
                label: "Visited",
                title: places.first(where: { $0.id == model.placeID })?.name
                    ?? model.location?.presentationAddress,
                systemImage: places.first(where: { $0.id == model.placeID })?.systemImage
                    ?? .mappin,
                action: onChooseLocation
            )
        }
    }
}

private struct PlaceVisitEditTimeSection: View {
    @Bindable var model: PlaceVisitEditModel

    var body: some View {
        Section("Time") {
            DatePicker("Started", selection: $model.startTime)
            DatePicker("Ended", selection: $model.endTime, in: model.startTime...)
        }
    }
}
