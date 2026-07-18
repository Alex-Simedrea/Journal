//
//  EntryLogSheet.swift
//  Journal
//

import SwiftData
import SwiftUI

struct EntryLogSheet: View {
    let selectedDay: TimelineDayKey
    let selectedDayEntries: [LogEntry]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Place.name) private var places: [Place]
    @Query(sort: \Person.name) private var people: [Person]
    @Query(sort: \TransitType.canonicalName) private var transitTypes: [TransitType]
    @State private var model = EntryComposerModel()

    var body: some View {
        NavigationStack {
            Form {
                EntryNaturalLanguageSection(model: model)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Describe Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    EntryLogConfirmationButton(
                        model: model,
                        places: places,
                        people: people,
                        transitTypes: transitTypes,
                        selectedDay: selectedDay,
                        selectedDayEntries: selectedDayEntries,
                        modelContext: modelContext,
                        onSaved: { dismiss() }
                    )
                }
            }
            .alert(
                "Couldn’t Log Entry",
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

private struct EntryNaturalLanguageSection: View {
    @Bindable var model: EntryComposerModel

    var body: some View {
        Section {
            TextField(
                "For example: Bolt from home to Kasho, or lunch at Magnolia",
                text: $model.input,
                axis: .vertical
            )
            .lineLimit(3...8)
            .disabled(model.isSaving)

            if model.isSaving {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Resolving your entry…")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Describe what happened")
        } footer: {
            Text("Journal determines whether this is transit or a place visit, then resolves saved places, people, time, and MapKit results.")
        }
    }
}

private struct EntryLogConfirmationButton: View {
    let model: EntryComposerModel
    let places: [Place]
    let people: [Person]
    let transitTypes: [TransitType]
    let selectedDay: TimelineDayKey
    let selectedDayEntries: [LogEntry]
    let modelContext: ModelContext
    let onSaved: () -> Void

    var body: some View {
        Button(role: .confirm) {
            Task {
                if await model.submit(
                    places: places,
                    people: people,
                    transitTypes: transitTypes,
                    selectedDay: selectedDay,
                    selectedDayEntries: selectedDayEntries,
                    modelContext: modelContext
                ) {
                    onSaved()
                }
            }
        }
        .disabled(!model.canSubmit)
    }
}
