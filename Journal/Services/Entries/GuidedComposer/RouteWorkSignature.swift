import Foundation

struct GuidedComposerRouteWorkSignature: Equatable, Hashable {
    let entryKind: ComposerEntryKind
    let routingMode: TransitRoutingMode
    let origin: Endpoint?
    let destination: Endpoint?
    let selectedDay: TimelineDayKey
    let timelineRevision: Int
    let repositoryGeneration: Int
    let currentLocation: LocationBucket?
    let currentLocationCapturedAt: Date?

    struct Endpoint: Equatable, Hashable {
        let id: String
        let location: LocationBucket

        init(_ candidate: ComposerLocationCandidate) {
            id = candidate.id
            location = LocationBucket(candidate.location)
        }
    }

    struct LocationBucket: Equatable, Hashable {
        let latitude: Int
        let longitude: Int

        init(
            _ location: Location,
            bucketSizeMeters: Double =
                GuidedComposerPolicy.currentLocationBucketMeters
        ) {
            let latitudeStep = bucketSizeMeters / 111_000
            let longitudeScale = max(
                cos(location.latitude * .pi / 180),
                0.1
            )
            let longitudeStep =
                bucketSizeMeters / (111_000 * longitudeScale)
            latitude = Int((location.latitude / latitudeStep).rounded())
            longitude = Int((location.longitude / longitudeStep).rounded())
        }
    }
}
