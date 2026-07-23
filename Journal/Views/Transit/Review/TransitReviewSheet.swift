//
//  TransitReviewSheet.swift
//  Journal
//

import SwiftData
import SwiftUI

struct TransitReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Place.name) private var places: [Place]
    @Query(sort: \Person.name) private var people: [Person]
    @Query(sort: \TransitType.canonicalName) private var transitTypes: [TransitType]

    let entry: LogEntry
    @State private var model: TransitReviewModel
    @State private var isConversionPresented = false
    @State private var presentedLocationEndpoint: TransitEndpoint?

    init(entry: LogEntry) {
        self.entry = entry
        _model = State(initialValue: TransitReviewModel(entry: entry))
    }

    var body: some View {
        NavigationStack {
            Form {
                TransitReviewExplanation()

                if model.reviewsEntryKind {
                    TransitEntryKindReviewSection(
                        reason: entry.entryKindReviewReason,
                        onSwitch: { isConversionPresented = true }
                    )
                }

                if model.reviewsTransitType {
                    TransitTypeReviewSection(
                        model: model,
                        transitTypes: transitTypes,
                        reason: model.reviewReason(
                            for: .transitType,
                            in: entry
                        )
                    )
                }

                if model.reviewsOrigin {
                    TransitOriginReviewSection(
                        model: model,
                        places: places,
                        candidates: entry.transitDetails?.originCandidates ?? [],
                        reason: model.reviewReason(for: .origin, in: entry),
                        onChooseLocation: {
                            presentedLocationEndpoint = .origin
                        }
                    )
                }

                if model.reviewsDestination {
                    TransitDestinationReviewSection(
                        model: model,
                        places: places,
                        candidates: entry.transitDetails?.destinationCandidates ?? [],
                        reason: model.reviewReason(for: .destination, in: entry),
                        onChooseLocation: {
                            presentedLocationEndpoint = .destination
                        }
                    )
                }

                if model.reviewsTime {
                    TransitTimeReviewSection(
                        model: model,
                        reason: model.reviewReason(for: .time, in: entry)
                    )
                }

                if model.reviewsPeople {
                    TransitPeopleReviewSection(
                        model: model,
                        people: people,
                        reason: model.reviewReason(for: .people, in: entry)
                    )
                }
            }
            .navigationTitle("Review Transit")
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
                            modelContext: modelContext
                        ) {
                            dismiss()
                        }
                    }
                    .disabled(!model.canSave)
                }
            }
            .alert(
                "Couldn’t Save Corrections",
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
                if model.transitType.isEmpty {
                    model.transitType = transitTypes.first?.canonicalName ?? ""
                }
            }
            .sheet(item: $model.addPlaceRequest) { request in
                AddPlaceSheet(
                    initialName: request.initialName,
                    initialSearchQuery: request.searchQuery,
                    initialLocation: request.initialLocation
                ) { place in
                    model.placeWasAdded(place, for: request.endpoint)
                }
            }
            .sheet(isPresented: $isConversionPresented) {
                EntryKindConversionSheet(
                    entry: entry,
                    targetKind: .placeVisit,
                    onConverted: { dismiss() }
                )
            }
            .sheet(item: $presentedLocationEndpoint) { endpoint in
                EntryLocationPickerSheet(
                    title: endpoint == .origin
                        ? "Choose Origin"
                        : "Choose Destination",
                    places: places
                ) {
                    model.selectLocation($0, for: endpoint)
                }
            }
        }
    }
}
