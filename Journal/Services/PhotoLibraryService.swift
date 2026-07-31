//
//  PhotoLibraryService.swift
//  Journal
//

import Photos
import UIKit

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

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
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
