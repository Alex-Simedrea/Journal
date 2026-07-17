//
//  PlaceDetailSheet.swift
//  Journal
//

import SwiftData
import SwiftUI

struct PlaceDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

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
                    lastVisitedAt: place.lastVisitedAt,
                    visitCount: place.visitCount
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
    let lastVisitedAt: Date
    let visitCount: Int

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
                if visitCount > 0 {
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
                Text(visitCount, format: .number)
            }
        }
    }
}
