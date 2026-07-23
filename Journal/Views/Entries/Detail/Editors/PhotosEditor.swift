import PhotosUI
import SwiftUI

struct EntryDetailPhotosEditor: View {
    @Bindable var session: EntryDetailEditSession
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isPickerPresented = false

    var body: some View {
        VStack(spacing: 12) {
            Button {
                isPickerPresented = true
            } label: {
                Label("Add Photos", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.background, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            LazyVStack(spacing: 8) {
                ForEach(session.photoReferences) { reference in
                    HStack(spacing: 10) {
                        EntryDetailPhotoThumbnail(reference: reference)
                            .frame(width: 58, height: 58)
                            .clipShape(.rect(cornerRadius: 12))
                        Text("Attached photo")
                        Spacer()
                        Button(role: .destructive) {
                            session.photoReferences.removeAll {
                                $0.id == reference.id
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    .padding(8)
                    .background(.background, in: .rect(cornerRadius: 16))
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
