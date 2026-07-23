//
//  PersonDetailSheet.swift
//  Journal
//

import SwiftData
import SwiftUI

struct PersonDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let person: Person

    var body: some View {
        NavigationStack {
            Form {
                PersonDetailAvatarSection(
                    name: person.name,
                    contactIdentifier: person.contactIdentifier
                )
                PersonDetailInformationSection(
                    name: person.name,
                    isContactBacked: person.contactIdentifier != nil
                )
            }
            .navigationTitle("Person Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    DeleteConfirmationButton(
                        accessibilityLabel: "Delete Person",
                        confirmationTitle: "Delete Person?",
                        confirmationMessage: "This person will be removed from your library and from existing entries.",
                        deleteAction: {
                            try JournalDeletionService.delete(
                                person,
                                in: modelContext
                            )
                        },
                        onDeleted: { dismiss() }
                    )
                }
            }
        }
    }
}

private struct PersonDetailAvatarSection: View {
    let name: String
    let contactIdentifier: String?

    var body: some View {
        Section {
            HStack {
                Spacer()
                PersonAvatar(
                    name: name,
                    contactIdentifier: contactIdentifier,
                    size: 88
                )
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }
}

private struct PersonDetailInformationSection: View {
    let name: String
    let isContactBacked: Bool

    var body: some View {
        Section("Details") {
            LabeledContent("Name", value: name)
            LabeledContent("Source") {
                if isContactBacked {
                    Text("Contacts")
                } else {
                    Text("Manual")
                }
            }
        }
    }
}
