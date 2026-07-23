//
//  AddPlaceSheet.swift
//  Journal
//

import MapKit
import SwiftData
import SwiftUI

struct AddPlaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let onSave: ((Place) -> Void)?
    private let capturesCurrentLocation: Bool
    @State private var model: PlaceEditorModel

    init(
        initialName: String = "",
        initialSearchQuery: String = "",
        initialLocation: Location? = nil,
        capturesCurrentLocation: Bool = true,
        onSave: ((Place) -> Void)? = nil
    ) {
        self.onSave = onSave
        self.capturesCurrentLocation = capturesCurrentLocation
        _model = State(
            initialValue: PlaceEditorModel(
                initialName: initialName,
                initialSearchQuery: initialSearchQuery,
                initialLocation: initialLocation,
                allowsCurrentLocationCapture: capturesCurrentLocation
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                PlaceEditorDetailsSection(model: model)
                PlaceEditorLocationSection(model: model)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        if let place = model.insertPlace(in: modelContext) {
                            onSave?(place)
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
        .task {
            if capturesCurrentLocation, model.location == nil {
                await model.captureCurrentLocation()
            }
        }
        .onDisappear {
            model.stop()
        }
    }
}
