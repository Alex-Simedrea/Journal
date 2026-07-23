//
//  JournalLanguageModelProvider.swift
//  Journal
//

import AnyLanguageModel
import Foundation

@MainActor
enum JournalLanguageModelProvider {
    static let modelName = "gpt-oss:120b"
    nonisolated static let endpoint = URL(string: "https://ollama.com/v1/")!

    static func configuredModel(recordResponses: Bool = false) throws -> OpenAILanguageModel {
        guard let apiKey = LanguageModelCredentialsStore().apiKey() else {
            throw LanguageModelConfigurationError.missingAPIKey
        }

        return OpenAILanguageModel(
            baseURL: endpoint,
            apiKey: apiKey,
            model: modelName,
            apiVariant: .chatCompletions,
            session: recordResponses
                ? LanguageModelRecordingSession.make()
                : makeDefaultSession()
        )
    }
}

enum LanguageModelConfigurationError: LocalizedError {
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            String(
                localized: "Add your Ollama Cloud API key in Settings before using AI features."
            )
        }
    }
}
