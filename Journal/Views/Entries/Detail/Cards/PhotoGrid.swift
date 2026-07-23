import MapKit
import Photos
import SwiftUI

struct EntryDetailPhotoGrid: View {
    let references: [PhotoReference]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        if references.isEmpty {
            ContentUnavailableView(
                "No Photos",
                systemImage: "photo.on.rectangle"
            )
            .frame(maxWidth: .infinity, minHeight: 100)
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(references) { reference in
                    EntryDetailPhotoThumbnail(reference: reference)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 22))
                }
            }
        }
    }
}

struct EntryDetailPhotoThumbnail: View {
    @Environment(\.displayScale) private var displayScale
    let reference: PhotoReference
    @State private var image: UIImage?
    @State private var didFinishLoading = false

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
            } else {
                ProgressView()
            }
        }
        .clipped()
        .task(id: reference.assetLocalIdentifier) {
            didFinishLoading = false
            image = await PhotoLibraryService.image(
                for: reference.assetLocalIdentifier,
                targetSize: CGSize(
                    width: 220 * displayScale,
                    height: 220 * displayScale
                )
            )
            didFinishLoading = true
        }
    }
}
