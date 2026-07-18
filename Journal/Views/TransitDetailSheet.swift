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

    var body: some View {
        NavigationStack {
            Form {
                if let details = entry.transitDetails {
                    TransitRouteMapSection(
                        origin: details.originPlace?.location
                            ?? details.originCandidates.first?.location,
                        destination: details.destinationPlace?.location
                            ?? details.destinationCandidates.first?.location
                    )
                    TransitEntrySummarySection(
                        transitType: details.type,
                        sourceOrganizationName: details.sourceOrganizationName,
                        sourceServiceIdentifier: details.sourceServiceIdentifier,
                        origin: details.originPlace?.name
                            ?? details.originRawText,
                        destination: details.destinationPlace?.name
                            ?? details.destinationRawText,
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
            .onChange(of: entry.kind) { _, kind in
                if kind != .transit {
                    dismiss()
                }
            }
        }
    }
}

private struct TransitRouteMapSection: View {
    let origin: Location?
    let destination: Location?

    var body: some View {
        if origin != nil || destination != nil {
            Section("Route") {
                Map(initialPosition: .automatic) {
                    if let origin {
                        Marker(
                            "Origin",
                            systemImage: "circle.fill",
                            coordinate: origin.coordinate
                        )
                        .tint(.blue)
                    }

                    if let destination {
                        Marker(
                            "Destination",
                            systemImage: "flag.fill",
                            coordinate: destination.coordinate
                        )
                        .tint(.red)
                    }
                }
                .frame(height: 220)
                .clipShape(.rect(cornerRadius: 12))
            }
        }
    }
}

private struct TransitEntrySummarySection: View {
    let transitType: String
    let sourceOrganizationName: String?
    let sourceServiceIdentifier: String?
    let origin: String?
    let destination: String?
    let startTime: Date?
    let endTime: Date?
    let startTimeZoneIdentifier: String
    let endTimeZoneIdentifier: String
    let timeConfidence: TimeConfidence
    let peopleNames: [String]
    let createdAt: Date
    let entryKindReviewReason: String?
    let fieldReviews: [TransitFieldReview]

    var body: some View {
        Section("Details") {
            LabeledContent("Type", value: transitType)
            if let sourceOrganizationName {
                LabeledContent("Pass issuer", value: sourceOrganizationName)
            }
            if let sourceServiceIdentifier {
                LabeledContent("Service", value: sourceServiceIdentifier)
            }
            LabeledContent("Origin", value: origin ?? "Unresolved")
            LabeledContent("Destination", value: destination ?? "Unresolved")
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
            LabeledContent("Time confidence", value: timeConfidence.title)

            if !peopleNames.isEmpty {
                LabeledContent("People", value: peopleNames.formatted())
            }

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

            if entryKindReviewReason != nil || !fieldReviews.isEmpty {
                TransitFieldReviewList(
                    entryKindReviewReason: entryKindReviewReason,
                    reviews: fieldReviews
                )
            }
        }
    }
}

private struct TransitFieldReviewList: View {
    let entryKindReviewReason: String?
    let reviews: [TransitFieldReview]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let entryKindReviewReason {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Entry type needs review")
                            .fontWeight(.semibold)
                        Text(entryKindReviewReason)
                            .font(.caption)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
            }
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
            }
        }
        .foregroundStyle(.orange)
    }
}

private extension TransitReviewField {
    var title: LocalizedStringResource {
        switch self {
        case .transitType: "Transit type needs review"
        case .origin: "Origin needs review"
        case .destination: "Destination needs review"
        case .time: "Time needs review"
        case .people: "People need review"
        }
    }
}

struct EntryDetailDateRow: View {
    let title: LocalizedStringResource
    let date: Date?
    let timeZoneIdentifier: String

    var body: some View {
        LabeledContent(title) {
            if let date {
                HStack(spacing: 5) {
                    Text(
                        date,
                        format: .dateTime
                            .day()
                            .month(.abbreviated)
                            .year()
                            .hour()
                            .minute()
                    )
                    if timeZoneIdentifier != TimeZone.current.identifier {
                        Text(timeZone.abbreviation(for: date) ?? timeZone.identifier)
                            .foregroundStyle(.secondary)
                    }
                }
                .environment(\.timeZone, timeZone)
            } else {
                Text("Unresolved")
            }
        }
    }

    private var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }
}

extension TimeConfidence {
    var title: String {
        switch self {
        case .explicit: "Explicit"
        case .inferredFromHistory: "Inferred from day history"
        case .inferredNearOrigin: "Inferred near origin"
        case .inferredNearDestination: "Inferred near destination"
        case .unresolved: "Unresolved"
        case .manualOverride: "Manually corrected"
        }
    }
}

struct EntryOriginalInputSection: View {
    let rawInput: String

    var body: some View {
        Section("Original input") {
            Text(rawInput)
                .textSelection(.enabled)
        }
    }
}

struct EntryModelExchangeSection: View {
    let instructions: String?
    let prompt: String?
    let toolTranscript: String?
    let response: String?

    var body: some View {
        Section("Model exchange") {
            if let instructions, let prompt, let response {
                NavigationLink("Session instructions") {
                    EntryModelPayloadView(
                        title: "Session Instructions",
                        content: instructions
                    )
                }

                NavigationLink("Full prompt") {
                    EntryModelPayloadView(
                        title: "Full Prompt",
                        content: prompt
                    )
                }

                if let toolTranscript {
                    NavigationLink("Tool calls and outputs") {
                        EntryModelPayloadView(
                            title: "Tool Calls and Outputs",
                            content: toolTranscript
                        )
                    }
                } else {
                    LabeledContent("Tool calls", value: "None")
                }

                NavigationLink("Exact response") {
                    EntryModelPayloadView(
                        title: "Exact Response",
                        content: response
                    )
                }
            } else {
                Text("The model exchange was not captured for this entry.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EntryModelPayloadView: View {
    let title: LocalizedStringResource
    let content: String

    var body: some View {
        ScrollView {
            Text(content)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
