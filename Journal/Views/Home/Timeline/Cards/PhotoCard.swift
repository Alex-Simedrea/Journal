import MapKit
import Photos
import SwiftUI

struct TimelinePhotoTile: View {
    let references: [PhotoReference]

    var body: some View {
        if references.count == 1, let reference = references.first {
            TimelinePhotoThumbnail(reference: reference)
                .clipShape(.rect(cornerRadius: 16))
        } else {
            GeometryReader { proxy in
                let visibleReferences = references.prefix(4)
                let rowCount: CGFloat = visibleReferences.count > 2 ? 2 : 1
                let gap: CGFloat = 6
                let cellWidth = (proxy.size.width - gap) / 2
                let rowHeight =
                    (proxy.size.height - gap * (rowCount - 1)) / rowCount

                ZStack(alignment: .topLeading) {
                    ForEach(
                        visibleReferences.enumerated(),
                        id: \.element.id
                    ) { index, reference in
                        TimelinePhotoThumbnail(reference: reference)
                            .overlay {
                                if index == 3, references.count > 4 {
                                    ZStack {
                                        Color.black.opacity(0.52)
                                        Text("+\(references.count - 4)")
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .frame(width: cellWidth, height: rowHeight)
                            .clipShape(.rect(cornerRadius: 9))
                            .offset(
                                x: index.isMultiple(of: 2)
                                    ? 0
                                    : cellWidth + gap,
                                y: index < 2 ? 0 : rowHeight + gap
                            )
                    }
                }
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .topLeading
                )
            }
        }
    }
}

struct TimelinePhotoThumbnail: View {
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
                TimelineFixedSymbol(
                    systemName: "photo.badge.exclamationmark",
                    size: 24
                )
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
                    width: 180 * displayScale,
                    height: 180 * displayScale
                )
            )
            didFinishLoading = true
        }
    }
}
