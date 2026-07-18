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
                        rawText: entry.transitDetails?.originRawText,
                        candidates: entry.transitDetails?.originCandidates ?? [],
                        reason: model.reviewReason(for: .origin, in: entry)
                    )
                }

                if model.reviewsDestination {
                    TransitDestinationReviewSection(
                        model: model,
                        places: places,
                        rawText: entry.transitDetails?.destinationRawText,
                        candidates: entry.transitDetails?.destinationCandidates ?? [],
                        reason: model.reviewReason(for: .destination, in: entry)
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
        }
    }
}

private struct TransitEntryKindReviewSection: View {
    let reason: String?
    let onSwitch: () -> Void

    var body: some View {
        Section {
            EntryReviewReason(reason: reason)
            LabeledContent("Selected type", value: "Transit")
            Button("Switch to Place Visit", action: onSwitch)
        } header: {
            Text("Entry type")
        } footer: {
            Text("Saving confirms this as transit.")
        }
    }
}

private struct TransitReviewExplanation: View {
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

private struct TransitTypeReviewSection: View {
    @Bindable var model: TransitReviewModel
    let transitTypes: [TransitType]
    let reason: String?

    var body: some View {
        Section("Transit type") {
            TransitFieldReviewReason(reason: reason)
            Picker("Type", selection: $model.transitType) {
                ForEach(transitTypes) { type in
                    Text(type.canonicalName).tag(type.canonicalName)
                }
                if !transitTypes.contains(where: {
                    $0.canonicalName == model.transitType
                }), !model.transitType.isEmpty {
                    Text(model.transitType).tag(model.transitType)
                }
            }
        }
    }
}

private struct TransitOriginReviewSection: View {
    @Bindable var model: TransitReviewModel
    let places: [Place]
    let rawText: String?
    let candidates: [PlaceCandidate]
    let reason: String?

    var body: some View {
        Section("Origin") {
            TransitFieldReviewReason(reason: reason)
            if let rawText {
                LabeledContent("From text", value: rawText)
            }

            Picker("Saved place", selection: $model.originPlaceID) {
                Text("Choose a place").tag(nil as UUID?)
                ForEach(places) { place in
                    Text(place.name).tag(place.id as UUID?)
                }
            }

            TransitPlaceCandidateList(
                candidates: candidates,
                fallbackText: rawText,
                onAdd: {
                    model.requestPlace(
                        for: .origin,
                        candidate: $0,
                        rawText: rawText
                    )
                }
            )
        }
    }
}

private struct TransitDestinationReviewSection: View {
    @Bindable var model: TransitReviewModel
    let places: [Place]
    let rawText: String?
    let candidates: [PlaceCandidate]
    let reason: String?

    var body: some View {
        Section("Destination") {
            TransitFieldReviewReason(reason: reason)
            if let rawText {
                LabeledContent("From text", value: rawText)
            }

            Picker("Saved place", selection: $model.destinationPlaceID) {
                Text("Choose a place").tag(nil as UUID?)
                ForEach(places) { place in
                    Text(place.name).tag(place.id as UUID?)
                }
            }

            TransitPlaceCandidateList(
                candidates: candidates,
                fallbackText: rawText,
                onAdd: {
                    model.requestPlace(
                        for: .destination,
                        candidate: $0,
                        rawText: rawText
                    )
                }
            )
        }
    }
}

private struct TransitPlaceCandidateList: View {
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
                    TransitPlaceCandidateMetrics(candidate: candidate)
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

private struct TransitPlaceCandidateMetrics: View {
    let candidate: PlaceCandidate

    var body: some View {
        HStack(spacing: 10) {
            if let distance = candidate.distanceKilometers {
                Label {
                    Text("\(distance, format: .number.precision(.fractionLength(1))) km")
                } icon: {
                    Image(systemName: "location")
                }
            }
            if let walking = candidate.walkingDurationMinutes {
                Label {
                    Text("\(walking, format: .number.precision(.fractionLength(0))) min")
                } icon: {
                    Image(systemName: "figure.walk")
                }
            }
            if let automobile = candidate.automobileDurationMinutes {
                Label {
                    Text("\(automobile, format: .number.precision(.fractionLength(0))) min")
                } icon: {
                    Image(systemName: "car")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

private struct TransitTimeReviewSection: View {
    @Bindable var model: TransitReviewModel
    let reason: String?

    var body: some View {
        Section("Time") {
            TransitFieldReviewReason(reason: reason)
            HStack {
                Button("Just now") { model.useJustNow() }
                    .buttonStyle(.bordered)
                Button("Earlier today") { model.useEarlierToday() }
                    .buttonStyle(.bordered)
            }

            DatePicker("Started", selection: $model.startTime)
            DatePicker("Ended", selection: $model.endTime, in: model.startTime...)
        }
    }
}

private struct TransitPeopleReviewSection: View {
    @Bindable var model: TransitReviewModel
    let people: [Person]
    let reason: String?

    var body: some View {
        Section("People") {
            TransitFieldReviewReason(reason: reason)
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

private struct TransitFieldReviewReason: View {
    let reason: String?

    var body: some View {
        if let reason, !reason.isEmpty {
            Label(reason, systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(.orange)
        }
    }
}
