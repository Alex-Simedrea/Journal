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

struct WorkoutSavedPlaceActions: View {
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
