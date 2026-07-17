//
//  AddPersonSheet.swift
//  Journal
//

import SwiftData
import SwiftUI
import UIKit

struct AddPersonSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onAdd: ((Person) -> Void)?

    init(onAdd: ((Person) -> Void)? = nil) {
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack {
            AddPersonOptions(
                onAdd: { person in
                    onAdd?(person)
                    dismiss()
                }
            )
            .navigationTitle("Add Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
        }
    }
}

private struct AddPersonOptions: View {
    let onAdd: (Person) -> Void

    var body: some View {
        List {
            NavigationLink {
                ContactImportView(onAdd: onAdd)
            } label: {
                Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus")
            }

            NavigationLink {
                ManualPersonView(onAdd: onAdd)
            } label: {
                Label("Add Manually", systemImage: "person.badge.plus")
            }
        }
    }
}

private struct ContactImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \Person.name) private var people: [Person]
    @State private var model = ContactImportModel()

    let onAdd: (Person) -> Void

    var body: some View {
        ContactImportContent(
            isLoading: model.isLoading,
            authorizationState: model.authorizationState,
            candidates: model.filteredCandidates,
            importedContactIdentifiers: model.importedContactIdentifiers,
            onSelect: importCandidate,
            onOpenSettings: openContactSettings
        )
        .navigationTitle("Import Contact")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $model.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Contacts"
        )
        .scrollDismissesKeyboard(.interactively)
        .task {
            model.updateImportedContacts(from: people)
            await model.load()
        }
        .alert(
            "Couldn’t Import Contact",
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

    private func importCandidate(_ candidate: ContactImportCandidate) {
        guard let person = model.importPerson(
            candidate: candidate,
            existingPeople: people,
            modelContext: modelContext
        ) else {
            return
        }
        onAdd(person)
    }

    private func openContactSettings() {
        guard let settingsURL = URL(
            string: UIApplication.openSettingsURLString
        ) else {
            return
        }
        openURL(settingsURL)
    }
}

private struct ContactImportContent: View {
    let isLoading: Bool
    let authorizationState: ContactAuthorizationState
    let candidates: [ContactImportCandidate]
    let importedContactIdentifiers: Set<String>
    let onSelect: (ContactImportCandidate) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        if isLoading {
            ProgressView("Loading Contacts…")
        } else if authorizationState == .denied {
            ContentUnavailableView {
                Label("Contacts Access Required", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("Allow contact access to import people and use their photos.")
            } actions: {
                Button("Open Settings", action: onOpenSettings)
            }
        } else if candidates.isEmpty {
            ContentUnavailableView(
                "No Contacts Available",
                systemImage: "person.crop.circle.badge.questionmark"
            )
        } else {
            List(candidates) { candidate in
                ContactImportRow(
                    candidate: candidate,
                    isImported: importedContactIdentifiers.contains(candidate.id),
                    onSelect: { onSelect(candidate) }
                )
            }
            .listStyle(.plain)
        }
    }
}

private struct ContactImportRow: View {
    let candidate: ContactImportCandidate
    let isImported: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                PersonAvatar(
                    name: candidate.name,
                    contactIdentifier: candidate.id,
                    size: 44
                )

                Text(candidate.name)
                    .foregroundStyle(.primary)

                Spacer()

                if isImported {
                    Label("Imported", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isImported)
    }
}

private struct ManualPersonView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model = ManualPersonEditorModel()

    let onAdd: (Person) -> Void

    var body: some View {
        Form {
            ManualPersonMonogram(name: model.name)

            Section("Details") {
                TextField("Name", text: $model.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(save)
            }
        }
        .navigationTitle("New Person")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!model.canSave)
            }
        }
        .alert(
            "Couldn’t Save Person",
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

    private func save() {
        guard let person = model.save(in: modelContext) else { return }
        onAdd(person)
    }
}

private struct ManualPersonMonogram: View {
    let name: String

    var body: some View {
        Section {
            HStack {
                Spacer()
                PersonAvatarImage(
                    name: name,
                    imageData: nil,
                    size: 88
                )
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }
}
