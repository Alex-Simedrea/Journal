//
//  DeleteConfirmationButton.swift
//  Journal
//

import SwiftUI

struct DeleteConfirmationButton: View {
    let accessibilityLabel: LocalizedStringResource
    let confirmationTitle: LocalizedStringResource
    let confirmationMessage: LocalizedStringResource
    let deleteAction: () throws -> Void
    let onDeleted: () -> Void

    @State private var isConfirmationPresented = false
    @State private var errorMessage: String?

    var body: some View {
        Button(role: .destructive) {
            isConfirmationPresented = true
        } label: {
            Image(systemName: "trash")
        }
        .accessibilityLabel(accessibilityLabel)
        .confirmationDialog(
            confirmationTitle,
            isPresented: $isConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .alert(
            "Couldn’t Delete",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private func delete() {
        do {
            try deleteAction()
            onDeleted()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
