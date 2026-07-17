import SwiftData
import SwiftUI

struct BoardingPassImportReviewSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Place.name) private var places: [Place]
    @Query(sort: \TransitType.canonicalName) private var transitTypes: [TransitType]

    let onComplete: (PendingBoardingPassImport) -> Void
    let onDefer: () -> Void
    let onDiscard: (PendingBoardingPassImport) -> Void

    @State private var model: BoardingPassReviewModel

    init(
        pendingImport: PendingBoardingPassImport,
        onComplete: @escaping (PendingBoardingPassImport) -> Void,
        onDefer: @escaping () -> Void,
        onDiscard: @escaping (PendingBoardingPassImport) -> Void
    ) {
        self.onComplete = onComplete
        self.onDefer = onDefer
        self.onDiscard = onDiscard
        _model = State(
            initialValue: BoardingPassReviewModel(
                pendingImport: pendingImport
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                BoardingPassImportSourceSection(
                    organizationName: model.pendingImport.organizationName,
                    serviceIdentifier: model.pendingImport.serviceIdentifier,
                    warnings: model.pendingImport.warnings
                )
                BoardingPassImportRouteSection(
                    model: model,
                    places: places,
                    transitTypes: transitTypes
                )
                BoardingPassImportTimeSection(
                    model: model,
                    originTimeZoneIdentifier: model.timeZoneIdentifier(
                        for: .origin,
                        places: places
                    ),
                    destinationTimeZoneIdentifier: model.timeZoneIdentifier(
                        for: .destination,
                        places: places
                    )
                )
                BoardingPassImportDiscardSection {
                    onDiscard(model.pendingImport)
                }
            }
            .navigationTitle("Review Boarding Pass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now", role: .cancel, action: onDefer)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", role: .confirm) {
                        if model.save(places: places, in: modelContext) {
                            onComplete(model.pendingImport)
                        }
                    }
                    .disabled(!model.canSave)
                }
            }
            .alert(
                "Couldn’t Import Boarding Pass",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "An unknown error occurred.")
            }
            .task(id: BoardingPassPreparationID(
                placeIDs: places.map(\.id),
                transitTypeNames: transitTypes.map(\.canonicalName)
            )) {
                model.prepare(places: places, transitTypes: transitTypes)
            }
            .sheet(item: $model.placeBeingAdded) { endpoint in
                AddPlaceSheet(
                    initialName: model.name(for: endpoint),
                    initialSearchQuery: model.name(for: endpoint)
                ) { place in
                    model.didAddPlace(place, for: endpoint)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

private struct BoardingPassPreparationID: Equatable {
    let placeIDs: [UUID]
    let transitTypeNames: [String]
}

private struct BoardingPassImportSourceSection: View {
    let organizationName: String?
    let serviceIdentifier: String?
    let warnings: [String]

    var body: some View {
        Section("Boarding Pass") {
            if let organizationName {
                LabeledContent("Issuer", value: organizationName)
            }
            if let serviceIdentifier {
                LabeledContent("Service", value: serviceIdentifier)
            }
            ForEach(warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct BoardingPassImportRouteSection: View {
    @Bindable var model: BoardingPassReviewModel
    let places: [Place]
    let transitTypes: [TransitType]

    var body: some View {
        Section("Route") {
            Picker("Type", selection: $model.transitType) {
                ForEach(transitTypes) { transitType in
                    Text(transitType.canonicalName)
                        .tag(transitType.canonicalName)
                }
            }

            BoardingPassEndpointPicker(
                title: "From",
                rawName: model.originName,
                selection: $model.originPlaceID,
                places: places,
                onAdd: { model.beginAddingPlace(for: .origin) }
            )
            BoardingPassEndpointPicker(
                title: "To",
                rawName: model.destinationName,
                selection: $model.destinationPlaceID,
                places: places,
                onAdd: { model.beginAddingPlace(for: .destination) }
            )
        }
    }
}

private struct BoardingPassEndpointPicker: View {
    let title: LocalizedStringResource
    let rawName: String
    @Binding var selection: UUID?
    let places: [Place]
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(title, selection: $selection) {
                Text("Not linked — \(rawName)").tag(nil as UUID?)
                ForEach(places) { place in
                    Text(place.name).tag(place.id as UUID?)
                }
            }

            if selection == nil {
                Button("Add \(rawName) to Places", action: onAdd)
                    .font(.subheadline)
            }
        }
    }
}

private struct BoardingPassImportTimeSection: View {
    @Bindable var model: BoardingPassReviewModel
    let originTimeZoneIdentifier: String
    let destinationTimeZoneIdentifier: String

    var body: some View {
        Section("Time") {
            DatePicker("Departure", selection: $model.startTime)
                .environment(
                    \.timeZone,
                    TimeZone(identifier: originTimeZoneIdentifier) ?? .current
                )
            DatePicker("Arrival", selection: $model.endTime, in: model.startTime...)
                .environment(
                    \.timeZone,
                    TimeZone(identifier: destinationTimeZoneIdentifier) ?? .current
                )
        }
    }
}

private struct BoardingPassImportDiscardSection: View {
    let onDiscard: () -> Void

    var body: some View {
        Section {
            Button("Discard Import", role: .destructive, action: onDiscard)
        }
    }
}
