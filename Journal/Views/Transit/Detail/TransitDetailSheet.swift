//
//  TransitDetailSheet.swift
//  Journal
//

import MapKit
import SwiftData
import SwiftUI

struct TransitDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let entry: LogEntry
    @State private var isReviewPresented = false
    @State private var isEditingPresented = false
    @State private var saveLocationRequest: SaveLocationAsPlaceRequest?

    var body: some View {
        NavigationStack {
            Form {
                if let details = entry.transitDetails {
                    TransitRouteMapSection(
                        origin: details.originLocation
                            ?? details.originPlace?.location
                            ?? details.originCandidates.first?.location,
                        destination: details.destinationLocation
                            ?? details.destinationPlace?.location
                            ?? details.destinationCandidates.first?.location
                    )
                    TransitEntrySummarySection(
                        transitType: details.type,
                        sourceOrganizationName: details.sourceOrganizationName,
                        sourceServiceIdentifier: details.sourceServiceIdentifier,
                        origin: details.originPlace?.name
                            ?? details.originLocation?.presentationAddress,
                        destination: details.destinationPlace?.name
                            ?? details.destinationLocation?.presentationAddress,
                        startTime: entry.startTime,
                        endTime: entry.endTime,
                        startTimeZoneIdentifier: entry.startTimeZoneIdentifier,
                        endTimeZoneIdentifier: entry.endTimeZoneIdentifier,
                        timeConfidence: entry.timeConfidence,
                        peopleNames: entry.people.map(\.name),
                        createdAt: entry.createdAt,
                        entryKindReviewReason: entry.entryKindReviewReason,
                        fieldReviews: details.fieldReviews
                    )
                    TransitSavedPlaceActions(
                        details: details,
                        onSelect: { saveLocationRequest = $0 }
                    )
                }

                EntryWeatherSection(entry: entry)

                EntryPhotoAttachmentsSection(entry: entry)

                if let rawInput = entry.rawInputString {
                    EntryOriginalInputSection(rawInput: rawInput)
                    EntryModelExchangeSection(
                        instructions: entry.modelInstructions,
                        prompt: entry.modelPrompt,
                        toolTranscript: entry.modelToolTranscript,
                        response: entry.modelResponse
                    )
                }
            }
            .navigationTitle("Transit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }

                ToolbarItem(placement: .destructiveAction) {
                    DeleteConfirmationButton(
                        accessibilityLabel: "Delete Entry",
                        confirmationTitle: "Delete Entry?",
                        confirmationMessage: "This entry will be permanently deleted from every day where it appears.",
                        deleteAction: {
                            try JournalDeletionService.delete(
                                entry,
                                in: modelContext
                            )
                        },
                        onDeleted: { dismiss() }
                    )
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    if entry.needsReview {
                        Button("Review") {
                            isReviewPresented = true
                        }
                    }

                    Button("Edit") {
                        isEditingPresented = true
                    }
                }
            }
            .sheet(isPresented: $isReviewPresented) {
                TransitReviewSheet(entry: entry)
            }
            .sheet(isPresented: $isEditingPresented) {
                TransitEditSheet(entry: entry)
            }
            .sheet(item: $saveLocationRequest) {
                SaveLocationAsPlaceSheet(request: $0)
            }
            .onChange(of: entry.kind) { _, kind in
                if kind != .transit {
                    dismiss()
                }
            }
        }
    }
}

struct TransitSavedPlaceActions: View {
    let details: TransitDetails
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
        var values: [EntryLocationSaveOption] = []
        if let location = details.originLocation {
            values.append(
                EntryLocationSaveOption(
                    id: "origin",
                    label: "Save Origin as Place",
                    name: details.originPlace?.name
                        ?? location.presentationAddress
                        ?? String(localized: "Origin"),
                    location: location,
                    isAlreadySaved: details.originPlace != nil
                )
            )
        }
        if let location = details.destinationLocation {
            values.append(
                EntryLocationSaveOption(
                    id: "destination",
                    label: "Save Destination as Place",
                    name: details.destinationPlace?.name
                        ?? location.presentationAddress
                        ?? String(localized: "Destination"),
                    location: location,
                    isAlreadySaved: details.destinationPlace != nil
                )
            )
        }
        return values
    }
}
