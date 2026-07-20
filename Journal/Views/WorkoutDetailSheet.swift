//
//  WorkoutDetailSheet.swift
//  Journal
//

import MapKit
import SwiftData
import SwiftUI

struct WorkoutDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let entry: LogEntry
    @State private var routeModel = WorkoutRouteModel()
    @State private var isPlacesPresented = false
    @State private var saveLocationRequest: SaveLocationAsPlaceRequest?

    var body: some View {
        NavigationStack {
            Form {
                if let details = entry.workoutDetails {
                    if details.movementKind == .moving {
                        WorkoutRouteSection(
                            workoutUUID: details.healthKitWorkoutUUID,
                            model: routeModel
                        )
                    }
                    WorkoutSummarySection(
                        activityName: details.activityName,
                        activityTypeRawValue: details.activityTypeRawValue,
                        movementKind: details.movementKind,
                        startTime: entry.startTime,
                        endTime: entry.endTime,
                        startTimeZoneIdentifier:
                            entry.startTimeZoneIdentifier,
                        endTimeZoneIdentifier:
                            entry.endTimeZoneIdentifier,
                        distanceMeters: details.distanceMeters,
                        activeEnergyKilocalories:
                            details.activeEnergyKilocalories,
                        placeName: WorkoutLocationPresentation.name(
                            place: details.place,
                            location: details.sourceLocation
                        ),
                        originName: WorkoutLocationPresentation.name(
                            place: details.originPlace,
                            location: details.originLocation
                        ),
                        destinationName: WorkoutLocationPresentation.name(
                            place: details.destinationPlace,
                            location: details.destinationLocation
                        ),
                        peopleNames: entry.people.map(\.name),
                        createdAt: entry.createdAt
                    )
                    WorkoutReviewSection(reviews: details.fieldReviews)
                    WorkoutSavedPlaceActions(
                        details: details,
                        onSelect: { saveLocationRequest = $0 }
                    )
                }

                EntryWeatherSection(entry: entry)
                EntryPhotoAttachmentsSection(entry: entry)
            }
            .navigationTitle("Workout Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    DeleteConfirmationButton(
                        accessibilityLabel: "Delete Workout Entry",
                        confirmationTitle: "Delete Workout Entry?",
                        confirmationMessage: "The workout remains in Health and will not be imported into Journal again.",
                        deleteAction: {
                            try JournalDeletionService.delete(
                                entry,
                                in: modelContext
                            )
                        },
                        onDeleted: { dismiss() }
                    )
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(entry.needsReview ? "Review" : "Edit") {
                        isPlacesPresented = true
                    }
                }
            }
            .sheet(isPresented: $isPlacesPresented) {
                WorkoutPlaceReviewSheet(entry: entry)
            }
            .sheet(item: $saveLocationRequest) {
                SaveLocationAsPlaceSheet(request: $0)
            }
            .onChange(of: entry.kind) { _, kind in
                if kind != .workout {
                    dismiss()
                }
            }
        }
    }
}

private struct WorkoutSavedPlaceActions: View {
    let details: WorkoutDetails
    let onSelect: (SaveLocationAsPlaceRequest) -> Void

    var body: some View {
        EntrySavedPlaceActionsSection(
            options: options,
            onSelect: { option in
                onSelect(
                    SaveLocationAsPlaceRequest(
                        name: option.name,
                        location: option.location
                    )
                )
            }
        )
    }

    private var options: [EntryLocationSaveOption] {
        if details.movementKind == .moving {
            return movingOptions
        }
        guard let location = details.sourceLocation else { return [] }
        return [
            EntryLocationSaveOption(
                id: "workout-place",
                label: "Save Location as Place",
                name: WorkoutLocationPresentation.name(
                    place: details.place,
                    location: location
                ),
                location: location,
                isAlreadySaved: details.place != nil
            ),
        ]
    }

    private var movingOptions: [EntryLocationSaveOption] {
        var values: [EntryLocationSaveOption] = []
        if let location = details.originLocation {
            values.append(
                EntryLocationSaveOption(
                    id: "workout-origin",
                    label: "Save Origin as Place",
                    name: WorkoutLocationPresentation.name(
                        place: details.originPlace,
                        location: location
                    ),
                    location: location,
                    isAlreadySaved: details.originPlace != nil
                )
            )
        }
        if let location = details.destinationLocation {
            values.append(
                EntryLocationSaveOption(
                    id: "workout-destination",
                    label: "Save Destination as Place",
                    name: WorkoutLocationPresentation.name(
                        place: details.destinationPlace,
                        location: location
                    ),
                    location: location,
                    isAlreadySaved: details.destinationPlace != nil
                )
            )
        }
        return values
    }
}

private struct WorkoutRouteSection: View {
    let workoutUUID: UUID
    let model: WorkoutRouteModel

    var body: some View {
        Section("Route") {
            WorkoutRouteContent(
                state: model.state,
                points: model.points,
                onRetry: {
                    Task { await model.load(workoutUUID: workoutUUID) }
                }
            )
        }
        .task(id: workoutUUID) {
            await model.load(workoutUUID: workoutUUID)
        }
    }
}

private struct WorkoutRouteContent: View {
    let state: WorkoutRouteLoadState
    let points: [WorkoutCoordinateSnapshot]
    let onRetry: () -> Void

    var body: some View {
        VStack {
            switch state {
            case .idle, .loading:
                ProgressView("Loading route…")
                    .frame(maxWidth: .infinity, minHeight: 180)
            case .loaded:
                WorkoutRouteMap(points: points)
            case .authorizationRequired:
                ContentUnavailableView {
                    Label("Health Access Required", systemImage: "heart.slash")
                } description: {
                    Text("Allow Journal to read workout routes in Health settings, then try again.")
                } actions: {
                    Button("Try Again", action: onRetry)
                }
                .frame(minHeight: 180)
            case .unavailable:
                ContentUnavailableView {
                    Label("Route Unavailable", systemImage: "map")
                } description: {
                    Text("Health does not currently provide a route for this workout.")
                }
                .frame(minHeight: 180)
            case .failed(let message):
                WorkoutRouteFailure(message: message, onRetry: onRetry)
            }
        }
    }
}

private struct WorkoutRouteMap: View {
    let points: [WorkoutCoordinateSnapshot]

    var body: some View {
        Map(initialPosition: .automatic) {
            MapPolyline(coordinates: points.map(\.coordinate))
                .stroke(.blue.gradient, lineWidth: 5)

            if let origin = points.first {
                Marker(
                    "Origin",
                    systemImage: "circle.fill",
                    coordinate: origin.coordinate
                )
                .tint(.blue)
            }

            if let destination = points.last {
                Marker(
                    "Destination",
                    systemImage: "flag.fill",
                    coordinate: destination.coordinate
                )
                .tint(.red)
            }
        }
        .frame(height: 280)
        .clipShape(.rect(cornerRadius: 12))
    }
}

private struct WorkoutRouteFailure: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Button("Retry", action: onRetry)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private struct WorkoutSummarySection: View {
    let activityName: String
    let activityTypeRawValue: Int
    let movementKind: WorkoutMovementKind
    let startTime: Date?
    let endTime: Date?
    let startTimeZoneIdentifier: String
    let endTimeZoneIdentifier: String
    let distanceMeters: Double?
    let activeEnergyKilocalories: Double?
    let placeName: String
    let originName: String
    let destinationName: String
    let peopleNames: [String]
    let createdAt: Date

    var body: some View {
        Section("Details") {
            LabeledContent("Activity") {
                Label(
                    activityName,
                    systemImage: WorkoutActivityCatalog.presentation(
                        for: activityTypeRawValue
                    ).systemImageName
                )
            }
            Label("Imported from Health", systemImage: "heart.fill")
                .foregroundStyle(.secondary)

            WorkoutPlaceSummaryRows(
                movementKind: movementKind,
                placeName: placeName,
                originName: originName,
                destinationName: destinationName
            )
            if !peopleNames.isEmpty {
                LabeledContent("People", value: peopleNames.formatted())
            }
            EntryDetailDateRow(
                title: "Started",
                date: startTime,
                timeZoneIdentifier: startTimeZoneIdentifier
            )
            EntryDetailDateRow(
                title: "Ended",
                date: endTime,
                timeZoneIdentifier: endTimeZoneIdentifier
            )
            WorkoutDurationRow(startTime: startTime, endTime: endTime)

            if movementKind == .moving {
                WorkoutDistanceRow(distanceMeters: distanceMeters)
            }
            WorkoutEnergyRow(
                activeEnergyKilocalories: activeEnergyKilocalories
            )

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
        }
    }
}

private struct WorkoutPlaceSummaryRows: View {
    let movementKind: WorkoutMovementKind
    let placeName: String
    let originName: String
    let destinationName: String

    var body: some View {
        if movementKind == .moving {
            LabeledContent("Origin", value: originName)
            LabeledContent(
                "Destination",
                value: destinationName
            )
        } else {
            LabeledContent("Place", value: placeName)
        }
    }
}

private struct WorkoutDurationRow: View {
    let startTime: Date?
    let endTime: Date?

    var body: some View {
        LabeledContent("Duration") {
            if let startTime, let endTime, endTime > startTime {
                Text(
                    Measurement(
                        value: endTime.timeIntervalSince(startTime) / 60,
                        unit: UnitDuration.minutes
                    ),
                    format: .measurement(width: .abbreviated)
                )
            } else {
                Text("Unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WorkoutDistanceRow: View {
    let distanceMeters: Double?

    var body: some View {
        LabeledContent("Distance") {
            if let distanceMeters {
                Text(
                    Measurement(
                        value: distanceMeters,
                        unit: UnitLength.meters
                    ),
                    format: .measurement(width: .abbreviated)
                )
            } else {
                Text("Unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WorkoutEnergyRow: View {
    let activeEnergyKilocalories: Double?

    var body: some View {
        LabeledContent("Active energy") {
            if let activeEnergyKilocalories {
                Text("\(activeEnergyKilocalories, format: .number.precision(.fractionLength(0...1))) kcal")
            } else {
                Text("Unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WorkoutReviewSection: View {
    let reviews: [WorkoutFieldReview]

    var body: some View {
        if !reviews.isEmpty {
            Section("Needs Review") {
                ForEach(reviews) { review in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(review.field.title)
                                .fontWeight(.semibold)
                            Text(review.reason)
                                .font(.caption)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                    }
                    .foregroundStyle(.orange)
                }
            }
        }
    }
}
