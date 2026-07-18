//
//  PlaceVisitReviewSheet.swift
//  Journal
//

import SwiftData
import SwiftUI

struct PlaceVisitReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Place.name) private var places: [Place]
    @Query(sort: \Person.name) private var people: [Person]

    let entry: LogEntry
    @State private var model: PlaceVisitReviewModel
    @State private var isConversionPresented = false

    init(entry: LogEntry) {
        self.entry = entry
        _model = State(initialValue: PlaceVisitReviewModel(entry: entry))
    }

    var body: some View {
        NavigationStack {
            Form {
                PlaceVisitReviewExplanation()
                if model.reviewsEntryKind {
                    PlaceVisitEntryKindReviewSection(
                        reason: entry.entryKindReviewReason,
                        onSwitch: { isConversionPresented = true }
                    )
                }
                if model.reviewsPlace {
                    PlaceVisitPlaceReviewSection(
                        model: model,
                        places: places,
                        rawText: entry.placeVisitDetails?.placeRawText,
                        candidates: entry.placeVisitDetails?.candidates ?? [],
                        reason: model.reviewReason(for: .place, in: entry)
                    )
                }
                if model.reviewsTime {
                    PlaceVisitTimeReviewSection(
                        model: model,
                        reason: model.reviewReason(for: .time, in: entry)
                    )
                }
                if model.reviewsPeople {
                    PlaceVisitPeopleReviewSection(
                        model: model,
                        people: people,
                        reason: model.reviewReason(for: .people, in: entry)
                    )
                }
            }
            .navigationTitle("Review Visit")
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
            .sheet(isPresented: $isConversionPresented) {
                EntryKindConversionSheet(
                    entry: entry,
                    targetKind: .transit,
                    onConverted: { dismiss() }
                )
            }
            .sheet(item: $model.addPlaceRequest) { request in
                AddPlaceSheet(
                    initialName: request.initialName,
                    initialSearchQuery: request.searchQuery,
                    initialLocation: request.initialLocation
                ) { place in
                    model.placeWasAdded(place)
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
        }
    }
}

private struct PlaceVisitReviewExplanation: View {
    var body: some View {
        Section {
            Label(
                "Only the uncertain parts of this entry are shown.",
                systemImage: "exclamationmark.circle.fill"
            )
            .foregroundStyle(.orange)
        }
    }
}

private struct PlaceVisitEntryKindReviewSection: View {
    let reason: String?
    let onSwitch: () -> Void

    var body: some View {
        Section {
            EntryReviewReason(reason: reason)
            LabeledContent("Selected type", value: "Place Visit")
            Button("Switch to Transit", action: onSwitch)
        } header: {
            Text("Entry type")
        } footer: {
            Text("Saving confirms this as a place visit.")
        }
    }
}

private struct PlaceVisitPlaceReviewSection: View {
    @Bindable var model: PlaceVisitReviewModel
    let places: [Place]
    let rawText: String?
    let candidates: [PlaceCandidate]
    let reason: String?

    var body: some View {
        Section("Place") {
            EntryReviewReason(reason: reason)
            if let rawText {
                LabeledContent("From text", value: rawText)
            }
            Picker("Saved place", selection: $model.placeID) {
                Text("Choose a place").tag(nil as UUID?)
                ForEach(places) { place in
                    Text(place.name).tag(place.id as UUID?)
                }
            }
            PlaceVisitCandidateList(
                candidates: candidates,
                fallbackText: rawText,
                onAdd: { model.requestPlace(candidate: $0, rawText: rawText) }
            )
        }
    }
}

private struct PlaceVisitCandidateList: View {
    let candidates: [PlaceCandidate]
    let fallbackText: String?
    let onAdd: (PlaceCandidate?) -> Void

    var body: some View {
        ForEach(candidates) { candidate in
            Button {
                onAdd(candidate)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Label(candidate.name, systemImage: "plus.circle")
                    if let address = candidate.address {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let distance = candidate.distanceKilometers {
                        Text(
                            "\(distance, format: .number.precision(.fractionLength(1))) km away"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        if candidates.isEmpty, fallbackText != nil {
            Button {
                onAdd(nil)
            } label: {
                Label("Save as a new place", systemImage: "plus.circle")
            }
        }
    }
}

private struct PlaceVisitTimeReviewSection: View {
    @Bindable var model: PlaceVisitReviewModel
    let reason: String?

    var body: some View {
        Section("Time") {
            EntryReviewReason(reason: reason)
            DatePicker("Started", selection: $model.startTime)
            DatePicker("Ended", selection: $model.endTime, in: model.startTime...)
        }
    }
}

private struct PlaceVisitPeopleReviewSection: View {
    @Bindable var model: PlaceVisitReviewModel
    let people: [Person]
    let reason: String?

    var body: some View {
        Section("People") {
            EntryReviewReason(reason: reason)
            ForEach($model.personResolutions) { $resolution in
                Picker(resolution.rawText, selection: $resolution.personID) {
                    Text("Choose a person").tag(nil as UUID?)
                    ForEach(people) { person in
                        Text(person.name).tag(person.id as UUID?)
                    }
                }
            }
        }
    }
}

struct EntryReviewReason: View {
    let reason: String?

    var body: some View {
        if let reason, !reason.isEmpty {
            Label(reason, systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(.orange)
        }
    }
}
