//
//  PlaceDetailSheet.swift
//  Journal
//

import SwiftData
import SwiftUI

struct PlaceDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [LogEntry]

    let place: Place
    @State private var model: PlaceEditorModel

    init(place: Place) {
        self.place = place
        _model = State(initialValue: PlaceEditorModel(place: place))
    }

    var body: some View {
        NavigationStack {
            Form {
                PlaceEditorDetailsSection(model: model)
                PlaceEditorLocationSection(model: model)
                PlaceMetadataSection(
                    createdAt: place.createdAt,
                    statistics: PlaceVisitStatisticsService
                        .calculate(from: entries)[
                            place.id,
                            default: PlaceVisitStatistics()
                        ]
                )
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Place Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .destructiveAction) {
                    DeleteConfirmationButton(
                        accessibilityLabel: "Delete Place",
                        confirmationTitle: "Delete Place?",
                        confirmationMessage: "This place will be removed from your library. Existing entries will remain.",
                        deleteAction: {
                            try JournalDeletionService.delete(
                                place,
                                in: modelContext
                            )
                        },
                        onDeleted: { dismiss() }
                    )
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        if model.update(place, in: modelContext) {
                            dismiss()
                        }
                    }
                    .disabled(!model.canSave)
                }
            }
            .alert(
                "Couldn’t Save Place",
                isPresented: Binding(
                    get: { model.saveErrorMessage != nil },
                    set: { if !$0 { model.saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.saveErrorMessage ?? "An unknown error occurred.")
            }
        }
        .onDisappear {
            model.stop()
        }
    }
}

private struct PlaceMetadataSection: View {
    let createdAt: Date
    let statistics: PlaceVisitStatistics

    var body: some View {
        Section("History") {
            LabeledContent("Created") {
                Text(
                    createdAt,
                    format: .dateTime
                        .day()
                        .month(.abbreviated)
                        .year()
                        .hour()
                        .minute()
                )
            }

            LabeledContent("Last visited") {
                if let lastVisitedAt = statistics.lastVisitedAt {
                    Text(
                        lastVisitedAt,
                        format: .dateTime
                            .day()
                            .month(.abbreviated)
                            .year()
                            .hour()
                            .minute()
                    )
                } else {
                    Text("Never")
                }
            }

            LabeledContent("Visits") {
                Text(statistics.visitCount, format: .number)
            }
        }
    }
}
