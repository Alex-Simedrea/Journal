import Foundation
import Photos

nonisolated struct PeriodPhotoMetadata: Equatable, Sendable {
    let isFavorite: Bool
    let creationDate: Date?
}

nonisolated enum PeriodPhotoMetadataService {
    static func metadata(
        for references: [PhotoReference]
    ) -> [String: PeriodPhotoMetadata] {
        let identifiers = Array(Set(references.map(\.assetLocalIdentifier)))
        guard !identifiers.isEmpty else { return [:] }
        let assets = PHAsset.fetchAssets(
            withLocalIdentifiers: identifiers,
            options: nil
        )
        var result: [String: PeriodPhotoMetadata] = [:]
        assets.enumerateObjects { asset, _, _ in
            result[asset.localIdentifier] = PeriodPhotoMetadata(
                isFavorite: asset.isFavorite,
                creationDate: asset.creationDate
            )
        }
        return result
    }
}
