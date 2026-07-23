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
    @State private var presentedLocation: ConversionLocationRole?

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
                EntryKindConversionFields(
                    model: model,
                    places: places,
                    onChooseLocation: { presentedLocation = $0 }
                )
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
            .sheet(item: $presentedLocation) { role in
                EntryLocationPickerSheet(
                    title: role.title,
                    places: places
                ) { selection in
                    switch role {
                    case .origin: model.selectOrigin(selection)
                    case .destination: model.selectDestination(selection)
                    case .visit: model.selectVisitLocation(selection)
                    }
                }
            }
        }
    }
}

private struct EntryKindConversionFields: View {
    @Bindable var model: EntryKindConversionModel
    let places: [Place]
    let onChooseLocation: (ConversionLocationRole) -> Void

    var body: some View {
        Group {
            if model.targetKind == .transit {
                Section("Route") {
                    TextField("Transit type", text: $model.transitType)
                    EntryLocationSelectionButton(
                        label: "From",
                        title: title(placeID: model.originPlaceID, location: model.originLocation),
                        systemImage: symbol(placeID: model.originPlaceID),
                        action: { onChooseLocation(.origin) }
                    )
                    EntryLocationSelectionButton(
                        label: "To",
                        title: title(
                            placeID: model.destinationPlaceID,
                            location: model.destinationLocation
                        ),
                        systemImage: symbol(placeID: model.destinationPlaceID),
                        action: { onChooseLocation(.destination) }
                    )
                }
            } else {
                Section("Place") {
                    EntryLocationSelectionButton(
                        label: "Visited",
                        title: title(
                            placeID: model.visitPlaceID,
                            location: model.visitLocation
                        ),
                        systemImage: symbol(placeID: model.visitPlaceID),
                        action: { onChooseLocation(.visit) }
                    )
                }
            }
        }
    }

    private func title(placeID: UUID?, location: Location?) -> String? {
        places.first(where: { $0.id == placeID })?.name
            ?? location?.presentationAddress
    }

    private func symbol(placeID: UUID?) -> PlaceSystemImage {
        places.first(where: { $0.id == placeID })?.systemImage ?? .mappin
    }
}

private enum ConversionLocationRole: String, Identifiable {
    case origin
    case destination
    case visit

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .origin: "Choose Origin"
        case .destination: "Choose Destination"
        case .visit: "Choose Location"
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
