//
//  AISettingsModel.swift
//  Journal
//

import Foundation
import Observation

enum APIKeySaveStatus: Equatable {
    case idle
    case saved
    case deleted
    case failed(String)
}

@MainActor
@Observable
final class AISettingsModel {
    var apiKey = ""
    private(set) var isKeyStored = false
    private(set) var status = APIKeySaveStatus.idle

    @ObservationIgnored
    private let credentialsStore = LanguageModelCredentialsStore()

    var canSave: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refresh() {
        isKeyStored = credentialsStore.apiKey() != nil
    }

    func save() {
        guard canSave else { return }

        if credentialsStore.saveAPIKey(apiKey) {
            apiKey = ""
            isKeyStored = true
            status = .saved
        } else {
            status = .failed(
                String(localized: "The API key could not be saved to Keychain.")
            )
        }
    }

    func delete() {
        guard credentialsStore.deleteAPIKey() else {
            status = .failed(
                String(localized: "The API key could not be removed from Keychain.")
            )
            return
        }

        apiKey = ""
        isKeyStored = false
        status = .deleted
    }
}
