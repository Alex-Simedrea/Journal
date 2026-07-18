//
//  WorkoutPlaceReviewSheet.swift
//  Journal
//

import MapKit
import SwiftData
import SwiftUI

struct WorkoutPlaceReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Place.name) private var places: [Place]

    let entry: LogEntry
    @State private var model: WorkoutPlaceReviewModel
    @State private var addPlaceRequest: WorkoutAddPlaceRequest?

    init(entry: LogEntry) {
        self.entry = entry
        _model = State(
            initialValue: WorkoutPlaceReviewModel(entry: entry)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                if let details = entry.workoutDetails {
                    WorkoutPlaceReviewExplanation(
                        movementKind: details.movementKind
                    )
                    WorkoutPlaceReviewSections(
                        details: details,
                        places: places,
                        model: model,
                        onAddPlace: { field, location in
                            addPlaceRequest = WorkoutAddPlaceRequest(
                                field: field,
                                location: location
                            )
                        }
                    )
                }
            }
            .navigationTitle("Workout Places")
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
                            in: modelContext
                        ) {
                            dismiss()
                        }
                    }
                }
            }
            .sheet(item: $addPlaceRequest) { request in
                AddPlaceSheet(
                    initialLocation: request.location,
                    capturesCurrentLocation: false,
                    onSave: { place in
                        model.select(place, for: request.field)
                    }
                )
            }
            .alert(
                "Couldn’t Save Workout Places",
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
    }
}

private struct WorkoutPlaceReviewExplanation: View {
    let movementKind: WorkoutMovementKind

    var body: some View {
        Section {
            if movementKind == .moving {
                Text("Confirm the saved places that match the first and last HealthKit route points.")
            } else {
                Text("Confirm where this workout happened. HealthKit-owned workout details remain read-only.")
            }
        }
    }
}

private struct WorkoutPlaceReviewSections: View {
    let details: WorkoutDetails
    let places: [Place]
    let model: WorkoutPlaceReviewModel
    let onAddPlace: (WorkoutReviewField, Location?) -> Void

    var body: some View {
        if details.movementKind == .moving {
            WorkoutPlaceSelectionSection(
                field: .origin,
                location: details.originLocation,
                reason: details.review(for: .origin)?.reason,
                places: places,
                model: model,
                onAddPlace: onAddPlace
            )
            WorkoutPlaceSelectionSection(
                field: .destination,
                location: details.destinationLocation,
                reason: details.review(for: .destination)?.reason,
                places: places,
                model: model,
                onAddPlace: onAddPlace
            )
        } else {
            WorkoutPlaceSelectionSection(
                field: .place,
                location: details.sourceLocation,
                reason: details.review(for: .place)?.reason,
                places: places,
                model: model,
                onAddPlace: onAddPlace
            )
        }
    }
}

private struct WorkoutPlaceSelectionSection: View {
    let field: WorkoutReviewField
    let location: Location?
    let reason: String?
    let places: [Place]
    @Bindable var model: WorkoutPlaceReviewModel
    let onAddPlace: (WorkoutReviewField, Location?) -> Void

    var body: some View {
        Section(field.title) {
            if let reason {
                Label(reason, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let location {
                WorkoutLocationPreview(
                    title: field.markerTitle,
                    location: location
                )
            }

            Picker(
                "Saved place (optional)",
                selection: $model[placeIDFor: field]
            ) {
                if location == nil {
                    Text("Unresolved").tag(nil as UUID?)
                } else {
                    Text("Use HealthKit Address").tag(nil as UUID?)
                }
                ForEach(places) { place in
                    Text(place.name).tag(place.id as UUID?)
                }
            }

            Button {
                onAddPlace(field, location)
            } label: {
                Label(
                    location == nil
                        ? "Add Place Manually"
                        : "Save Location as New Place",
                    systemImage: "plus"
                )
            }
        }
    }
}

private struct WorkoutLocationPreview: View {
    let title: String
    let location: Location

    var body: some View {
        Map(initialPosition: .region(region)) {
            Marker(title, coordinate: location.coordinate)
        }
        .frame(height: 170)
        .clipShape(.rect(cornerRadius: 12))
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
    }
}

private struct WorkoutAddPlaceRequest: Identifiable {
    let field: WorkoutReviewField
    let location: Location?

    var id: WorkoutReviewField { field }
}

private extension WorkoutReviewField {
    var markerTitle: String {
        switch self {
        case .place: String(localized: "Workout location")
        case .origin: String(localized: "Origin")
        case .destination: String(localized: "Destination")
        }
    }
}
