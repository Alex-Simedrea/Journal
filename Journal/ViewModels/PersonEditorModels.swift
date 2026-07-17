//
//  PersonEditorModels.swift
//  Journal
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ContactImportModel {
    var searchText = "" {
        didSet { updateFilteredCandidates() }
    }
    private(set) var candidates: [ContactImportCandidate] = []
    private(set) var filteredCandidates: [ContactImportCandidate] = []
    private(set) var authorizationState: ContactAuthorizationState = .notDetermined
    private(set) var importedContactIdentifiers: Set<String> = []
    private(set) var isLoading = false
    var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            authorizationState = try await ContactsService.shared
                .requestAccessIfNeeded()
            candidates = try await ContactsService.shared.importCandidates()
            updateFilteredCandidates()
        } catch {
            authorizationState = await ContactsService.shared
                .authorizationState()
            candidates = []
            filteredCandidates = []
            errorMessage = error.localizedDescription
        }
    }

    func importPerson(
        candidate: ContactImportCandidate,
        existingPeople: [Person],
        modelContext: ModelContext
    ) -> Person? {
        guard !existingPeople.contains(where: {
            $0.contactIdentifier == candidate.id
        }) else {
            errorMessage = String(
                localized: "This contact has already been imported."
            )
            return nil
        }

        let person = Person(
            name: candidate.name,
            contactIdentifier: candidate.id
        )
        modelContext.insert(person)

        do {
            try modelContext.save()
            return person
        } catch {
            modelContext.delete(person)
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateImportedContacts(from people: [Person]) {
        importedContactIdentifiers = Set(
            people.compactMap(\.contactIdentifier)
        )
    }

    private func updateFilteredCandidates() {
        let query = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty else {
            filteredCandidates = candidates
            return
        }
        filteredCandidates = candidates.filter {
            $0.name.localizedStandardContains(query)
        }
    }
}

@MainActor
@Observable
final class ManualPersonEditorModel {
    var name = ""
    var errorMessage: String?

    var canSave: Bool {
        !trimmedName.isEmpty
    }

    func save(in modelContext: ModelContext) -> Person? {
        guard canSave else { return nil }

        let person = Person(name: trimmedName)
        modelContext.insert(person)
        do {
            try modelContext.save()
            return person
        } catch {
            modelContext.delete(person)
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
