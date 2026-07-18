//
//  PersonEditorModels.swift
//  Journal
//

import Foundation
import Observation
import SwiftData

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
