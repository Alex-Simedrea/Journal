//
//  SettingsScreen.swift
//  Journal
//

import SwiftUI

struct SettingsScreen: View {
    @State private var model = AISettingsModel()

    var body: some View {
        NavigationStack {
            Form {
                OllamaModelSection()
                OllamaCredentialSection(model: model)
            }
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.interactively)
            .task {
                model.refresh()
            }
        }
    }
}

private struct OllamaModelSection: View {
    var body: some View {
        Section("Language Model") {
            LabeledContent("Provider", value: "Ollama Cloud")
            LabeledContent("Model", value: JournalLanguageModelProvider.modelName)
            LabeledContent(
                "Endpoint",
                value: JournalLanguageModelProvider.endpoint.absoluteString
            )
        }
    }
}

private struct OllamaCredentialSection: View {
    @Bindable var model: AISettingsModel

    var body: some View {
        Section {
            SecureField("Ollama API key", text: $model.apiKey)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()
                .submitLabel(.done)
                .onSubmit {
                    model.save()
                }

            Button("Save API Key") {
                model.save()
            }
            .disabled(!model.canSave)

            if model.isKeyStored {
                Button("Remove API Key", role: .destructive) {
                    model.delete()
                }
            }

            APIKeyStatusRow(
                isKeyStored: model.isKeyStored,
                status: model.status
            )
        } header: {
            Text("Authentication")
        } footer: {
            Text("The key is stored only in this device's Keychain and is sent as a bearer token to Ollama Cloud.")
        }
    }
}

private struct APIKeyStatusRow: View {
    let isKeyStored: Bool
    let status: APIKeySaveStatus

    var body: some View {
        Label(message, systemImage: systemImage)
            .foregroundStyle(color)
    }

    private var message: String {
        switch status {
        case .idle:
            isKeyStored ? "API key saved" : "No API key saved"
        case .saved:
            "API key saved"
        case .deleted:
            "API key removed"
        case .failed(let message):
            message
        }
    }

    private var systemImage: String {
        switch status {
        case .failed:
            "exclamationmark.triangle.fill"
        default:
            isKeyStored ? "checkmark.circle.fill" : "key"
        }
    }

    private var color: Color {
        switch status {
        case .failed:
            .red
        default:
            isKeyStored ? .green : .secondary
        }
    }
}

#Preview {
    SettingsScreen()
}
