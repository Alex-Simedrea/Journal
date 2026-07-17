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

    let mode: TransitComposerMode
    @State private var model = TransitComposerModel()

    var body: some View {
        NavigationStack {
            Form {
                if mode == .naturalLanguage {
                    TransitNaturalLanguageSection(model: model)
                } else {
                    TransitManualRouteSection(
                        model: model,
                        places: places,
                        transitTypes: transitTypes
                    )
                    TransitManualTimeSection(model: model)
                    TransitPeopleSection(model: model, people: people)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(mode == .naturalLanguage ? "Log Transit" : "Manual Transit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    TransitLogConfirmationButton(
                        mode: mode,
                        model: model,
                        places: places,
                        people: people,
                        transitTypes: transitTypes,
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

private struct TransitNaturalLanguageSection: View {
    @Bindable var model: TransitComposerModel

    var body: some View {
        Section {
            TextField(
                "For example: Bolt from home to Reyna beach",
                text: $model.naturalLanguageInput,
                axis: .vertical
            )
            .lineLimit(3...8)
            .disabled(model.isSaving)

            if model.isSaving {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Resolving your trip…")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Describe the trip")
        } footer: {
            Text("Journal uses your saved places, people, current location, and MapKit to resolve the entry on device.")
        }
    }
}

private struct TransitManualRouteSection: View {
    @Bindable var model: TransitComposerModel
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
    @Bindable var model: TransitComposerModel

    var body: some View {
        Section("Time") {
            DatePicker("Started", selection: $model.startTime)
            DatePicker("Ended", selection: $model.endTime, in: model.startTime...)
        }
    }
}

private struct TransitPeopleSection: View {
    let model: TransitComposerModel
    let people: [Person]

    var body: some View {
        if !people.isEmpty {
            Section("People") {
                ForEach(people) { person in
                    TransitPersonSelectionRow(
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

private struct TransitPersonSelectionRow: View {
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

private struct TransitLogConfirmationButton: View {
    let mode: TransitComposerMode
    let model: TransitComposerModel
    let places: [Place]
    let people: [Person]
    let transitTypes: [TransitType]
    let modelContext: ModelContext
    let onSaved: () -> Void

    var body: some View {
        Button(role: .confirm) {
            if mode == .naturalLanguage {
                Task {
                    if await model.submitNaturalLanguage(
                        places: places,
                        people: people,
                        transitTypes: transitTypes,
                        modelContext: modelContext
                    ) {
                        onSaved()
                    }
                }
            } else if model.saveManual(
                places: places,
                people: people,
                modelContext: modelContext
            ) {
                onSaved()
            }
        }
        .disabled(
            mode == .naturalLanguage
                ? !model.canSubmitNaturalLanguage
                : !model.canSaveManual
        )
    }
}
