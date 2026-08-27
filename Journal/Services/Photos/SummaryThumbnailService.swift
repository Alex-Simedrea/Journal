//
//  SummaryThumbnailService.swift
//  Journal
//

import UIKit

@MainActor
final class SummaryImageMemoryCache {
    static let shared = SummaryImageMemoryCache()

    private let cache: NSCache<NSString, UIImage>

    private init() {
        cache = NSCache()
        cache.countLimit = 512
        cache.totalCostLimit = 96 * 1_024 * 1_024
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, forKey key: String, cost: Int) {
        cache.setObject(
            image,
            forKey: key as NSString,
            cost: max(cost, 1)
        )
    }
}

@MainActor
enum SummaryPhotoThumbnailService {
    private static let pixelDimension = 256

    static func cachedImage(for reference: PhotoReference) -> UIImage? {
        SummaryImageMemoryCache.shared.image(forKey: key(for: reference))
    }

    static func image(for reference: PhotoReference) async -> UIImage? {
        if let cached = cachedImage(for: reference) { return cached }
        guard let image = await PhotoLibraryService.image(
            for: reference.assetLocalIdentifier,
            targetSize: CGSize(
                width: pixelDimension,
                height: pixelDimension
            )
        ) else { return nil }
        SummaryImageMemoryCache.shared.insert(
            image,
            forKey: key(for: reference),
            cost: imageCost(image)
        )
        return image
    }

    static func prewarm(_ references: [PhotoReference]) async {
        let identifiers = Array(Set(
            references.map(\.assetLocalIdentifier)
        ))
        PhotoLibraryService.preheatImages(
            for: identifiers,
            targetSize: CGSize(
                width: pixelDimension,
                height: pixelDimension
            )
        )
    }

    private static func key(for reference: PhotoReference) -> String {
        "summary-photo/\(reference.assetLocalIdentifier)/\(pixelDimension)"
    }

    private static func imageCost(_ image: UIImage) -> Int {
        guard let image = image.cgImage else { return pixelDimension * pixelDimension * 4 }
        return image.bytesPerRow * image.height
    }
}
