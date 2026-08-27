//
//  PhotoLibraryService.swift
//  Journal
//

import Photos
import UIKit

@MainActor
private final class PhotoLibraryImageRequest {
    private let manager: PHImageManager
    private let asset: PHAsset
    private let targetSize: CGSize
    private let options: PHImageRequestOptions
    private var requestID = PHInvalidImageRequestID
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var isFinished = false

    init(
        manager: PHImageManager,
        asset: PHAsset,
        targetSize: CGSize,
        options: PHImageRequestOptions
    ) {
        self.manager = manager
        self.asset = asset
        self.targetSize = targetSize
        self.options = options
    }

    func value() async -> UIImage? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                requestID = manager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFill,
                    options: options
                ) { [weak self] image, info in
                    Task { @MainActor in
                        guard let self else { return }
                        let wasCancelled = info?[PHImageCancelledKey]
                            as? Bool ?? false
                        let error = info?[PHImageErrorKey] as? (any Error)
                        self.finish(
                            with: wasCancelled || error != nil ? nil : image
                        )
                    }
                }
                if Task.isCancelled { self.cancel() }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    private func cancel() {
        guard !isFinished else { return }
        if requestID != PHInvalidImageRequestID {
            manager.cancelImageRequest(requestID)
        }
        finish(with: nil)
    }

    private func finish(with image: UIImage?) {
        guard !isFinished else { return }
        isFinished = true
        continuation?.resume(returning: image)
        continuation = nil
    }
}

nonisolated enum PhotoLibraryServiceError: LocalizedError {
    case accessDenied
    case inaccessibleSelection
    case previewUnavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            String(localized: "Photos access is required to keep references to attached images. You can enable it in Settings.")
        case .inaccessibleSelection:
            String(localized: "One or more selected photos aren’t available to Journal. Allow access to those photos and try again.")
        case .previewUnavailable:
            String(localized: "This photo isn’t available for preview.")
        }
    }
}

@MainActor
enum PhotoLibraryService {
    private static let cachingImageManager = PHCachingImageManager()

    static func requestReadAccess() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryServiceError.accessDenied
        }
    }

    static func accessibleIdentifiers(
        from identifiers: [String]
    ) -> Set<String> {
        let assets = PHAsset.fetchAssets(
            withLocalIdentifiers: identifiers,
            options: nil
        )
        var accessibleIdentifiers = Set<String>()
        assets.enumerateObjects { asset, _, _ in
            accessibleIdentifiers.insert(asset.localIdentifier)
        }
        return accessibleIdentifiers
    }

    static func image(
        for assetLocalIdentifier: String,
        targetSize: CGSize
    ) async -> UIImage? {
        let assets = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetLocalIdentifier],
            options: nil
        )
        guard let asset = assets.firstObject else { return nil }

        let image = await PhotoLibraryImageRequest(
            manager: cachingImageManager,
            asset: asset,
            targetSize: targetSize,
            options: thumbnailOptions()
        ).value()
        guard let image else { return nil }
        let prepared = await image.byPreparingForDisplay() ?? image
        return Task.isCancelled ? nil : prepared
    }

    static func preheatImages(
        for assetLocalIdentifiers: [String],
        targetSize: CGSize
    ) {
        guard !assetLocalIdentifiers.isEmpty else { return }
        let assets = PHAsset.fetchAssets(
            withLocalIdentifiers: assetLocalIdentifiers,
            options: nil
        )
        var values: [PHAsset] = []
        values.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in values.append(asset) }
        guard !values.isEmpty else { return }
        cachingImageManager.startCachingImages(
            for: values,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: thumbnailOptions()
        )
    }

    private static func thumbnailOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        return options
    }

    static func temporaryPreviewURL(
        for assetLocalIdentifier: String
    ) async throws -> URL {
        let assets = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetLocalIdentifier],
            options: nil
        )
        guard let asset = assets.firstObject else {
            throw PhotoLibraryServiceError.previewUnavailable
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource =
            resources.first(where: { $0.type == .fullSizePhoto })
                ?? resources.first(where: { $0.type == .photo })
                ?? resources.first
        else {
            throw PhotoLibraryServiceError.previewUnavailable
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "JournalPhotoPreview-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let originalFilename = URL(
            fileURLWithPath: resource.originalFilename
        ).lastPathComponent
        let filename = originalFilename.isEmpty
            ? "Photo"
            : originalFilename
        let previewURL = directory.appendingPathComponent(filename)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(
                    for: resource,
                    toFile: previewURL,
                    options: options
                ) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            return previewURL
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func removeTemporaryPreview(at url: URL) {
        try? FileManager.default.removeItem(
            at: url.deletingLastPathComponent()
        )
    }
}
