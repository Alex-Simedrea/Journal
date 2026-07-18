//
//  AddPersonSheet.swift
//  Journal
//

import SwiftData
import SwiftUI

struct AddPersonSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onAdd: ((Person) -> Void)?

    init(onAdd: ((Person) -> Void)? = nil) {
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack {
            ManualPersonView(
                onAdd: { person in
                    onAdd?(person)
                    dismiss()
                }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
        }
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
