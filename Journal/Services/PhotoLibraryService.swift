//
//  PhotoLibraryService.swift
//  Journal
//

import Photos
import UIKit

nonisolated enum PhotoLibraryServiceError: LocalizedError {
    case accessDenied
    case inaccessibleSelection

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            String(localized: "Photos access is required to keep references to attached images. You can enable it in Settings.")
        case .inaccessibleSelection:
            String(localized: "One or more selected photos aren’t available to Journal. Allow access to those photos and try again.")
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
}
