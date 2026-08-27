import CoreLocation
import Foundation
import Photos
import SwiftData

nonisolated struct AutomaticPhotoMetadata: Hashable, Sendable {
    let assetLocalIdentifier: String
    let creationDate: Date
    let latitude: Double
    let longitude: Double

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

nonisolated enum AutomaticPhotoMatchGeometry: Hashable, Sendable {
    case staticLocation(latitude: Double, longitude: Double, radiusMeters: Double)
    case corridor(
        originLatitude: Double,
        originLongitude: Double,
        destinationLatitude: Double,
        destinationLongitude: Double
    )
}

nonisolated struct AutomaticPhotoMatchTarget: Hashable, Sendable {
    let entryID: UUID
    let startTime: Date
    let endTime: Date
    let geometry: AutomaticPhotoMatchGeometry
}

nonisolated enum PhotoAutoLinkService {
    nonisolated static let minimumStaticRadiusMeters = 250.0
    nonisolated static let corridorMultiplier = 1.25
    nonisolated static let corridorAllowanceMeters = 2_000.0

    static func synchronize(in modelContext: ModelContext) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }

        let matchInput = try matchTargets(in: modelContext)
        let targetsByEntryID = matchInput.targets
        guard !targetsByEntryID.isEmpty else { return }

        let intervals = mergedIntervals(
            Array(targetsByEntryID.values).map {
                DateInterval(start: $0.startTime, end: $0.endTime)
            }
        )
        let matchesByEntryID = await Task.detached(priority: .utility) {
            let photos = photoMetadata(in: intervals)
            guard !photos.isEmpty else { return [UUID: [String]]() }

            return targetsByEntryID.mapValues { target in
                photos.compactMap { photo in
                    matches(photo, target: target)
                        ? photo.assetLocalIdentifier
                        : nil
                }
            }
        }.value
        guard !matchesByEntryID.isEmpty else { return }

        var changed = false
        for (entryID, matchingIdentifiers) in matchesByEntryID {
            guard let entry = matchInput.entriesByID[entryID] else { continue }
            var identifiers = Set(
                entry.photoReferences.map(\.assetLocalIdentifier)
            )
            for assetLocalIdentifier in matchingIdentifiers {
                guard identifiers.insert(assetLocalIdentifier).inserted
                else { continue }
                entry.photoReferences.append(
                    PhotoReference(
                        assetLocalIdentifier: assetLocalIdentifier
                    )
                )
                changed = true
            }
        }

        guard changed else { return }
        do {
            try modelContext.save()
            await TimelineDataChange.post()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    static func matchingPhotoReferences(
        for entry: LogEntry
    ) async -> [PhotoReference] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited,
              let target = target(for: entry) else {
            return []
        }

        let identifiers = await Task.detached(priority: .utility) {
            photoMetadata(
                in: [
                    DateInterval(
                        start: target.startTime,
                        end: target.endTime
                    ),
                ]
            ).compactMap { photo in
                matches(photo, target: target)
                    ? photo.assetLocalIdentifier
                    : nil
            }
        }.value
        return identifiers.map {
            PhotoReference(assetLocalIdentifier: $0)
        }
    }

    private static func matchTargets(
        in modelContext: ModelContext
    ) throws -> (
        targets: [UUID: AutomaticPhotoMatchTarget],
        entriesByID: [UUID: LogEntry]
    ) {
        let entries = try modelContext.fetch(
            FetchDescriptor<LogEntry>(
                predicate: #Predicate {
                    $0.startTime != nil && $0.endTime != nil
                }
            )
        )
        var targets: [UUID: AutomaticPhotoMatchTarget] = [:]
        var entriesByID: [UUID: LogEntry] = [:]
        for entry in entries {
            guard let target = target(for: entry) else { continue }
            targets[entry.id] = target
            entriesByID[entry.id] = entry
        }
        return (targets, entriesByID)
    }

    nonisolated static func matches(
        _ photo: AutomaticPhotoMetadata,
        target: AutomaticPhotoMatchTarget
    ) -> Bool {
        guard photo.creationDate >= target.startTime,
              photo.creationDate <= target.endTime else {
            return false
        }

        switch target.geometry {
        case .staticLocation(let latitude, let longitude, let radiusMeters):
            let center = CLLocation(latitude: latitude, longitude: longitude)
            return photo.location.distance(from: center) <= radiusMeters
        case .corridor(
            let originLatitude,
            let originLongitude,
            let destinationLatitude,
            let destinationLongitude
        ):
            let origin = CLLocation(
                latitude: originLatitude,
                longitude: originLongitude
            )
            let destination = CLLocation(
                latitude: destinationLatitude,
                longitude: destinationLongitude
            )
            let direct = origin.distance(from: destination)
            guard direct > 1 else { return false }
            let viaPhoto = origin.distance(from: photo.location)
                + photo.location.distance(from: destination)
            let maximum = max(
                direct * corridorMultiplier,
                direct + corridorAllowanceMeters
            )
            return viaPhoto <= maximum
        }
    }

    private static func target(
        for entry: LogEntry
    ) -> AutomaticPhotoMatchTarget? {
        guard let startTime = entry.startTime,
              let endTime = entry.endTime,
              endTime > startTime else {
            return nil
        }

        let geometry: AutomaticPhotoMatchGeometry?
        switch entry.kind {
        case .placeVisit:
            let details = entry.placeVisitDetails
            let location = details?.location ?? details?.place?.location
            geometry = location.map {
                .staticLocation(
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    radiusMeters: max(
                        minimumStaticRadiusMeters,
                        details?.place?.accuracyRadiusMeters ?? 0
                    )
                )
            }
        case .transit:
            let details = entry.transitDetails
            geometry = corridor(
                origin: details?.originLocation
                    ?? details?.originPlace?.location,
                destination: details?.destinationLocation
                    ?? details?.destinationPlace?.location
            )
        case .workout:
            guard let details = entry.workoutDetails else { return nil }
            switch details.movementKind {
            case .staticWorkout:
                let location = details.sourceLocation
                    ?? details.place?.location
                geometry = location.map {
                    .staticLocation(
                        latitude: $0.latitude,
                        longitude: $0.longitude,
                        radiusMeters: max(
                            minimumStaticRadiusMeters,
                            details.place?.accuracyRadiusMeters ?? 0
                        )
                    )
                }
            case .moving:
                geometry = corridor(
                    origin: details.originLocation
                        ?? details.originPlace?.location,
                    destination: details.destinationLocation
                        ?? details.destinationPlace?.location
                )
            }
        case .wakeUp:
            geometry = nil
        }

        return geometry.map {
            AutomaticPhotoMatchTarget(
                entryID: entry.id,
                startTime: startTime,
                endTime: endTime,
                geometry: $0
            )
        }
    }

    private static func corridor(
        origin: Location?,
        destination: Location?
    ) -> AutomaticPhotoMatchGeometry? {
        guard let origin, let destination else { return nil }
        return .corridor(
            originLatitude: origin.latitude,
            originLongitude: origin.longitude,
            destinationLatitude: destination.latitude,
            destinationLongitude: destination.longitude
        )
    }

    nonisolated private static func photoMetadata(
        in intervals: [DateInterval]
    ) -> [AutomaticPhotoMetadata] {
        var result: [String: AutomaticPhotoMetadata] = [:]
        for interval in intervals {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate <= %@",
                interval.start as NSDate,
                interval.end as NSDate
            )
            let assets = PHAsset.fetchAssets(with: .image, options: options)
            assets.enumerateObjects { asset, _, _ in
                guard let creationDate = asset.creationDate,
                      let location = asset.location else { return }
                result[asset.localIdentifier] = AutomaticPhotoMetadata(
                    assetLocalIdentifier: asset.localIdentifier,
                    creationDate: creationDate,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
            }
        }
        return result.values.sorted {
            if $0.creationDate != $1.creationDate {
                return $0.creationDate < $1.creationDate
            }
            return $0.assetLocalIdentifier < $1.assetLocalIdentifier
        }
    }

    private static func mergedIntervals(
        _ intervals: [DateInterval]
    ) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for interval in sorted {
            guard let last = result.last else {
                result.append(interval)
                continue
            }
            if interval.start <= last.end {
                result[result.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                result.append(interval)
            }
        }
        return result
    }
}
