//
//  EntryPhotoAttachmentsModel.swift
//  Journal
//

import Observation
import PhotosUI
import SwiftData
import SwiftUI

@MainActor
@Observable
final class EntryPhotoAttachmentsModel {
    var selectedItems: [PhotosPickerItem] = []
    var isPickerPresented = false
    var isRequestingAccess = false
    var errorMessage: String?

    func presentPicker() async {
        isRequestingAccess = true
        errorMessage = nil
        defer { isRequestingAccess = false }

        do {
            try await PhotoLibraryService.requestReadAccess()
            isPickerPresented = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func attachSelectedItems(
        to entry: LogEntry,
        in modelContext: ModelContext
    ) {
        guard !selectedItems.isEmpty else { return }

        let selectedItemCount = selectedItems.count
        let identifiers = selectedItems.compactMap(\.itemIdentifier)
        selectedItems = []

        guard identifiers.count == selectedItemCount else {
            errorMessage = PhotoLibraryServiceError
                .inaccessibleSelection
                .localizedDescription
            return
        }

        let accessibleIdentifiers = PhotoLibraryService
            .accessibleIdentifiers(from: identifiers)
        guard accessibleIdentifiers.count == Set(identifiers).count else {
            errorMessage = PhotoLibraryServiceError
                .inaccessibleSelection
                .localizedDescription
            return
        }

        let originalReferences = entry.photoReferences
        var knownIdentifiers = Set(
            originalReferences.map(\.assetLocalIdentifier)
        )
        let newReferences = identifiers.compactMap {
            identifier -> PhotoReference? in
            guard knownIdentifiers.insert(identifier).inserted else {
                return nil
            }
            return PhotoReference(assetLocalIdentifier: identifier)
        }
        guard !newReferences.isEmpty else { return }

        entry.photoReferences.append(contentsOf: newReferences)
        save(
            entry: entry,
            restoring: originalReferences,
            in: modelContext
        )
    }

    func remove(
        _ reference: PhotoReference,
        from entry: LogEntry,
        in modelContext: ModelContext
    ) {
        let originalReferences = entry.photoReferences
        entry.photoReferences.removeAll { $0.id == reference.id }
        save(
            entry: entry,
            restoring: originalReferences,
            in: modelContext
        )
    }

    private func save(
        entry: LogEntry,
        restoring originalReferences: [PhotoReference],
        in modelContext: ModelContext
    ) {
        do {
            try modelContext.save()
        } catch {
            entry.photoReferences = originalReferences
            errorMessage = error.localizedDescription
        }
    }
}
