//
//  PlaceVisitDetailSheet.swift
//  Journal
//

import MapKit
import SwiftData
import SwiftUI

struct PlaceVisitDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let entry: LogEntry
    @State private var isReviewPresented = false
    @State private var isEditingPresented = false

    var body: some View {
        NavigationStack {
            Form {
                if let details = entry.placeVisitDetails {
                    PlaceVisitMapSection(
                        name: details.place?.name
                            ?? details.placeRawText
                            ?? "Visited place",
                        systemImage: details.place?.systemImage ?? .mappin,
                        location: details.place?.location
                            ?? details.candidates.first?.location
                    )
                    PlaceVisitSummarySection(
                        placeName: details.place?.name
                            ?? details.placeRawText,
                        startTime: entry.startTime,
                        endTime: entry.endTime,
                        timeZoneIdentifier: entry.startTimeZoneIdentifier,
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
            .navigationTitle("Visit Details")
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
                        Button("Review") { isReviewPresented = true }
                    }
                    Button("Edit") { isEditingPresented = true }
                }
            }
            .sheet(isPresented: $isReviewPresented) {
                PlaceVisitReviewSheet(entry: entry)
            }
            .sheet(isPresented: $isEditingPresented) {
                PlaceVisitEditSheet(entry: entry)
            }
            .onChange(of: entry.kind) { _, kind in
                if kind != .placeVisit {
                    dismiss()
                }
            }
        }
    }
}

private struct PlaceVisitMapSection: View {
    let name: String
    let systemImage: PlaceSystemImage
    let location: Location?

    var body: some View {
        if let location {
            Section("Location") {
                Map(initialPosition: .automatic) {
                    Marker(
                        name,
                        systemImage: systemImage.rawValue,
                        coordinate: location.coordinate
                    )
                }
                .frame(height: 220)
                .clipShape(.rect(cornerRadius: 12))
            }
        }
    }
}

private struct PlaceVisitSummarySection: View {
    let placeName: String?
    let startTime: Date?
    let endTime: Date?
    let timeZoneIdentifier: String
    let timeConfidence: TimeConfidence
    let peopleNames: [String]
    let createdAt: Date
    let entryKindReviewReason: String?
    let fieldReviews: [PlaceVisitFieldReview]

    var body: some View {
        Section("Details") {
            LabeledContent("Place", value: placeName ?? "Unresolved")
            EntryDetailDateRow(
                title: "Started",
                date: startTime,
                timeZoneIdentifier: timeZoneIdentifier
            )
            EntryDetailDateRow(
                title: "Ended",
                date: endTime,
                timeZoneIdentifier: timeZoneIdentifier
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
            PlaceVisitReviewList(
                entryKindReviewReason: entryKindReviewReason,
                reviews: fieldReviews
            )
        }
    }
}

private struct PlaceVisitReviewList: View {
    let entryKindReviewReason: String?
    let reviews: [PlaceVisitFieldReview]

    var body: some View {
        if entryKindReviewReason != nil || !reviews.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let entryKindReviewReason {
                    PlaceVisitReviewLabel(
                        title: "Entry type needs review",
                        reason: entryKindReviewReason
                    )
                }
                ForEach(reviews) { review in
                    PlaceVisitReviewLabel(
                        title: review.field.title,
                        reason: review.reason
                    )
                }
            }
            .foregroundStyle(.orange)
        }
    }
}

private struct PlaceVisitReviewLabel: View {
    let title: LocalizedStringResource
    let reason: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(reason).font(.caption)
            }
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
    }
}

private extension PlaceVisitReviewField {
    var title: LocalizedStringResource {
        switch self {
        case .place: "Place needs review"
        case .time: "Time needs review"
        case .people: "People need review"
        }
    }
}
