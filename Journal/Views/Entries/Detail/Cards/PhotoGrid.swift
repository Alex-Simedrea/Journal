import MapKit
import Photos
import QuickLook
import SwiftUI

struct EntryDetailPhotoGrid: View {
    let references: [PhotoReference]
    @State private var previewURL: URL?
    @State private var previewFailure: PhotoPreviewFailure?
    @State private var showsPreviewFailure = false
    @State private var previewTask: Task<Void, Never>?
    @State private var previewRequestID = UUID()

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
                    Button {
                        preparePreview(for: reference)
                    } label: {
                        EntryDetailPhotoThumbnail(reference: reference)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 22))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preview photo")
                }
            }
            .quickLookPreview($previewURL)
            .alert(
                "Unable to Preview Photo",
                isPresented: $showsPreviewFailure,
                presenting: previewFailure
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { failure in
                Text(failure.message)
            }
            .onChange(of: previewURL) { oldValue, newValue in
                if oldValue != newValue, let oldValue {
                    PhotoLibraryService.removeTemporaryPreview(at: oldValue)
                }
            }
            .onDisappear(perform: discardPreview)
        }
    }

    private func preparePreview(for reference: PhotoReference) {
        previewTask?.cancel()
        previewRequestID = UUID()
        let requestID = previewRequestID
        previewFailure = nil
        showsPreviewFailure = false

        previewTask = Task {
            do {
                let url = try await PhotoLibraryService
                    .temporaryPreviewURL(
                        for: reference.assetLocalIdentifier
                    )
                guard !Task.isCancelled,
                      previewRequestID == requestID else {
                    PhotoLibraryService.removeTemporaryPreview(at: url)
                    return
                }
                previewTask = nil
                previewURL = url
            } catch {
                guard !Task.isCancelled,
                      previewRequestID == requestID else {
                    return
                }
                previewTask = nil
                previewFailure = PhotoPreviewFailure(
                    message: error.localizedDescription
                )
                showsPreviewFailure = true
            }
        }
    }

    private func discardPreview() {
        previewTask?.cancel()
        previewTask = nil
        previewRequestID = UUID()
        if let previewURL {
            PhotoLibraryService.removeTemporaryPreview(at: previewURL)
            self.previewURL = nil
        }
    }
}

private struct PhotoPreviewFailure {
    let message: String
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
