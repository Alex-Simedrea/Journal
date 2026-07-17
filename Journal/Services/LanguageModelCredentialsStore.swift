//
//  LanguageModelCredentialsStore.swift
//  Journal
//

import Foundation
import KeychainSwift

@MainActor
struct LanguageModelCredentialsStore {
    private static let apiKeyKey = "ollamaCloudAPIKey"

    private let keychain = KeychainSwift(keyPrefix: "ro.attractivestar.Journal.")

    func apiKey() -> String? {
        guard let value = keychain.get(Self.apiKeyKey)?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !value.isEmpty else {
            return nil
        }

        return value
    }

    func saveAPIKey(_ value: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return false }

        return keychain.set(
            trimmedValue,
            forKey: Self.apiKeyKey,
            withAccess: .accessibleWhenUnlockedThisDeviceOnly
        )
    }

    func deleteAPIKey() -> Bool {
        keychain.delete(Self.apiKeyKey)
    }
}
