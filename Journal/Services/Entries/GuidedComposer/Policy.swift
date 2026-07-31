import Foundation

enum GuidedComposerPolicy {
    nonisolated static let minimumInferenceGap: TimeInterval = 5 * 60
    nonisolated static let minimumRouteAlternativeDifference: TimeInterval =
        5 * 60
    nonisolated static let minimumCurrentLocationRadiusMeters = 200.0
    nonisolated static let currentLocationTimeToLive: TimeInterval = 5 * 60
    nonisolated static let currentLocationFailureRetryInterval:
        TimeInterval = 60
    nonisolated static let currentLocationBucketMeters = 100.0
    nonisolated static let duplicateLocationRadiusMeters = 100.0
    nonisolated static let coordinateIdentityRadiusMeters = 25.0
    nonisolated static let maximumHomeDistanceMeters = 100_000.0
}

enum GuidedComposerTransitFamily {
    private nonisolated static let rideShareCanonicalNames = Set([
        "ride share",
        "uber",
        "bolt",
        "lyft",
        "taxi",
    ])

    private nonisolated static let rideShareSearchTerms = Set([
        "ride share",
        "rideshare",
        "ride hailing",
        "ride-hailing",
        "uber",
        "bolt",
        "lyft",
        "taxi",
        "cab",
    ])

    nonisolated static func isRideShareSearchTerm(_ value: String) -> Bool {
        rideShareSearchTerms.contains(GuidedComposerNormalization.text(value))
    }

    nonisolated static func areRelated(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        rideShareCanonicalNames.contains(
            GuidedComposerNormalization.text(lhs)
        ) && rideShareCanonicalNames.contains(
            GuidedComposerNormalization.text(rhs)
        )
    }
}
