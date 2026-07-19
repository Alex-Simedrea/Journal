//
//  TransitEditSheet.swift
//  Journal
//

import SwiftData
import SwiftUI

struct TransitEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Place.name) private var places: [Place]
    @Query(sort: \Person.name) private var people: [Person]
    @Query(sort: \TransitType.canonicalName) private var transitTypes: [TransitType]

    let entry: LogEntry
    @State private var model: TransitEditModel
    @State private var presentedEndpoint: TransitEditLocationEndpoint?

    init(entry: LogEntry) {
        self.entry = entry
        _model = State(initialValue: TransitEditModel(entry: entry))
    }

    var body: some View {
        NavigationStack {
            Form {
                TransitEditRouteSection(
                    model: model,
                    places: places,
                    transitTypes: transitTypes,
                    onChooseOrigin: { presentedEndpoint = .origin },
                    onChooseDestination: { presentedEndpoint = .destination }
                )
                TransitEditTimeSection(model: model)
                TransitEditPeopleSection(model: model, people: people)
            }
            .navigationTitle("Edit Transit")
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
                "Couldn’t Save Transit",
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
            .sheet(item: $presentedEndpoint) { endpoint in
                EntryLocationPickerSheet(
                    title: endpoint == .origin
                        ? "Choose Origin"
                        : "Choose Destination",
                    places: places
                ) { selection in
                    switch endpoint {
                    case .origin: model.selectOrigin(selection)
                    case .destination: model.selectDestination(selection)
                    }
                }
            }
        }
    }
}

private struct TransitEditRouteSection: View {
    @Bindable var model: TransitEditModel
    let places: [Place]
    let transitTypes: [TransitType]
    let onChooseOrigin: () -> Void
    let onChooseDestination: () -> Void

    var body: some View {
        Section("Route") {
            Picker("Type", selection: $model.transitType) {
                ForEach(transitTypes) { type in
                    Text(type.canonicalName).tag(type.canonicalName)
                }
                if !model.transitType.isEmpty,
                   !transitTypes.contains(where: {
                       $0.canonicalName == model.transitType
                   }) {
                    Text(model.transitType).tag(model.transitType)
                }
            }

            EntryLocationSelectionButton(
                label: "From",
                title: selectionTitle(
                    placeID: model.originPlaceID,
                    location: model.originLocation
                ),
                systemImage: selectionSymbol(placeID: model.originPlaceID),
                action: onChooseOrigin
            )

            EntryLocationSelectionButton(
                label: "To",
                title: selectionTitle(
                    placeID: model.destinationPlaceID,
                    location: model.destinationLocation
                ),
                systemImage: selectionSymbol(placeID: model.destinationPlaceID),
                action: onChooseDestination
            )
        }
    }

    private func selectionTitle(placeID: UUID?, location: Location?) -> String? {
        places.first(where: { $0.id == placeID })?.name
            ?? location?.presentationAddress
    }

    private func selectionSymbol(placeID: UUID?) -> PlaceSystemImage {
        places.first(where: { $0.id == placeID })?.systemImage ?? .mappin
    }
}

private enum TransitEditLocationEndpoint: String, Identifiable {
    case origin
    case destination

    var id: String { rawValue }
}

private struct TransitEditTimeSection: View {
    @Bindable var model: TransitEditModel

    var body: some View {
        Section("Time") {
            DatePicker("Started", selection: $model.startTime)
            DatePicker("Ended", selection: $model.endTime, in: model.startTime...)
        }
    }
}

private struct TransitEditPeopleSection: View {
    let model: TransitEditModel
    let people: [Person]

    var body: some View {
        Section("People") {
            if people.isEmpty {
                Text("No people available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(people) { person in
                    TransitEditPersonRow(
                        name: person.name,
                        contactIdentifier: person.contactIdentifier,
                        isSelected: model.selectedPeopleIDs.contains(person.id),
                        onSelect: { model.togglePerson(person.id) }
                    )
                }
            }
        }
    }
}

private struct TransitEditPersonRow: View {
    let name: String
    let contactIdentifier: String?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                PersonAvatar(
                    name: name,
                    contactIdentifier: contactIdentifier,
                    size: 34
                )
                Text(name)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
    }
}
