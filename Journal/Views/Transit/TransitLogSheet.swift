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
    @State private var presentedEndpoint: TransitLocationEndpoint?

    var body: some View {
        NavigationStack {
            Form {
                TransitManualRouteSection(
                    model: model,
                    places: places,
                    transitTypes: transitTypes,
                    onChooseOrigin: { presentedEndpoint = .origin },
                    onChooseDestination: { presentedEndpoint = .destination }
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
        .interactiveDismissDisabled(model.isSaving)
    }
}

private struct TransitManualRouteSection: View {
    @Bindable var model: ManualTransitComposerModel
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

private enum TransitLocationEndpoint: String, Identifiable {
    case origin
    case destination

    var id: String { rawValue }
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
