//
//  EntryPhotoAttachmentsSection.swift
//  Journal
//

import Photos
import PhotosUI
import SwiftData
import SwiftUI

struct EntryPhotoAttachmentsSection: View {
    @Environment(\.modelContext) private var modelContext

    let entry: LogEntry
    @State private var model = EntryPhotoAttachmentsModel()

    var body: some View {
        Section("Photos") {
            EntryPhotoAttachmentContent(
                references: entry.photoReferences,
                isRequestingAccess: model.isRequestingAccess,
                onAdd: {
                    Task { await model.presentPicker() }
                },
                onRemove: {
                    model.remove($0, from: entry, in: modelContext)
                }
            )
        }
        .photosPicker(
            isPresented: $model.isPickerPresented,
            selection: $model.selectedItems,
            maxSelectionCount: nil,
            selectionBehavior: .ordered,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: model.selectedItems) { _, _ in
            model.attachSelectedItems(to: entry, in: modelContext)
        }
        .alert(
            "Couldn’t Attach Photos",
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
}

private struct EntryPhotoAttachmentContent: View {
    let references: [PhotoReference]
    let isRequestingAccess: Bool
    let onAdd: () -> Void
    let onRemove: (PhotoReference) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if references.isEmpty {
                Label("No attached photos", systemImage: "photo.on.rectangle")
                    .foregroundStyle(.secondary)
            } else {
                EntryPhotoStrip(
                    references: references,
                    onRemove: onRemove
                )
            }

            Button(action: onAdd) {
                Label("Add Photos", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .disabled(isRequestingAccess)
            .overlay {
                if isRequestingAccess {
                    ProgressView()
                }
            }
        }
    }
}

private struct EntryPhotoStrip: View {
    let references: [PhotoReference]
    let onRemove: (PhotoReference) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(references) { reference in
                    EntryPhotoTile(
                        reference: reference,
                        onRemove: { onRemove(reference) }
                    )
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct EntryPhotoTile: View {
    @Environment(\.displayScale) private var displayScale

    let reference: PhotoReference
    let onRemove: () -> Void
    @State private var image: UIImage?
    @State private var didFinishLoading = false

    private let dimension: CGFloat = 112

    var body: some View {
        ZStack(alignment: .topTrailing) {
            EntryPhotoThumbnail(
                image: image,
                didFinishLoading: didFinishLoading
            )
            .frame(width: dimension, height: dimension)
            .clipShape(.rect(cornerRadius: 12))

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.65))
                    .font(.title3)
            }
            .padding(5)
            .accessibilityLabel("Remove attached photo")
        }
        .task(id: reference.assetLocalIdentifier) {
            didFinishLoading = false
            image = await PhotoLibraryService.image(
                for: reference.assetLocalIdentifier,
                targetSize: CGSize(
                    width: dimension * displayScale,
                    height: dimension * displayScale
                )
            )
            didFinishLoading = true
        }
    }
}

private struct EntryPhotoThumbnail: View {
    let image: UIImage?
    let didFinishLoading: Bool

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.12)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if didFinishLoading {
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Photo unavailable")
            } else {
                ProgressView()
            }
        }
    }
}
