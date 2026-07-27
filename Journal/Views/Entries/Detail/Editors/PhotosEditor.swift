import PhotosUI
import SwiftUI

struct EntryDetailPhotosEditor: View {
    @Bindable var session: EntryDetailEditSession
    @Binding var isPickerPresented: Bool
    @State private var selectedItems: [PhotosPickerItem] = []

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        Group {
            if session.photoReferences.isEmpty {
                ContentUnavailableView(
                    "No Photos",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text(
                        "Use the add button to attach photos to this entry."
                    )
                )
                .frame(maxWidth: .infinity, minHeight: 180)
                .dynamicSheetSurface()
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(session.photoReferences) { reference in
                        EntryDetailPhotoEditorCell(reference: reference) {
                            session.photoReferences.removeAll {
                                $0.id == reference.id
                            }
                        }
                    }
                    .reorderable()
                }
                .reorderContainer(for: PhotoReference.self) { difference in
                    switch difference.destination.position {
                    case .before(let destinationID):
                        session.movePhotos(
                            difference.sources,
                            before: destinationID
                        )
                    case .end:
                        session.movePhotos(difference.sources, before: nil)
                    }
                }
            }
        }
        .photosPicker(
            isPresented: $isPickerPresented,
            selection: $selectedItems,
            maxSelectionCount: nil,
            selectionBehavior: .ordered,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selectedItems) { _, items in
            let existing = Set(session.photoReferences.map(\.assetLocalIdentifier))
            let references = items.compactMap { item -> PhotoReference? in
                guard let identifier = item.itemIdentifier,
                      !existing.contains(identifier) else { return nil }
                return PhotoReference(assetLocalIdentifier: identifier)
            }
            session.photoReferences.append(contentsOf: references)
            selectedItems = []
        }
    }
}

private struct EntryDetailPhotoEditorCell: View {
    let reference: PhotoReference
    let onRemove: () -> Void

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                EntryDetailPhotoThumbnail(reference: reference)
            }
            .clipShape(.rect(cornerRadius: 24))
            .overlay(alignment: .topTrailing) {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash.fill")
                        .resizable()
                        .frame(width: 16, height: 16)
                        .padding(4)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(.red)
                .padding(8)
                .accessibilityLabel("Remove Photo")
            }
            .contentShape(
                [.interaction, .dragPreview],
                .rect(cornerRadius: 24)
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Attached Photo")
            .accessibilityHint("Touch and hold, then drag to reorder")
    }
}
