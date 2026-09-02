import CoreLocation
import Foundation

nonisolated enum WorkoutTimelinePlaceReconciler {
    static let maximumTimeDelta: TimeInterval = 5 * 60
    static let maximumEndpointDistanceMeters: CLLocationDistance = 150

    @discardableResult
    static func reconcile(entries: [LogEntry]) -> Bool {
        let ordered = entries.sorted(by: entryOrder)
        var changed = false

        for index in ordered.indices {
            let entry = ordered[index]
            guard entry.kind == .workout,
                  let details = entry.workoutDetails,
                  details.movementKind == .moving else {
                continue
            }

            if details.originResolutionSource == .automatic,
               let startTime = entry.startTime,
               index > ordered.startIndex,
               let endpoint = details.originLocation,
               let candidate = endCandidate(for: ordered[index - 1]),
               isCloseInTime(candidate.date, startTime),
               isCloseInSpace(endpoint, candidate.location) {
                changed = associate(
                    candidate.place,
                    with: .origin,
                    in: details
                ) || changed
            }

            let nextIndex = index + 1
            if details.destinationResolutionSource == .automatic,
               let endTime = entry.endTime,
               nextIndex < ordered.endIndex,
               let endpoint = details.destinationLocation,
               let candidate = startCandidate(for: ordered[nextIndex]),
               isCloseInTime(endTime, candidate.date),
               isCloseInSpace(endpoint, candidate.location) {
                changed = associate(
                    candidate.place,
                    with: .destination,
                    in: details
                ) || changed
            }

            let needsReview = !details.fieldReviews.isEmpty
            if entry.needsReview != needsReview {
                entry.needsReview = needsReview
                changed = true
            }
        }

        return changed
    }

    private static func entryOrder(_ lhs: LogEntry, _ rhs: LogEntry) -> Bool {
        let lhsDate = lhs.startTime ?? lhs.endTime ?? lhs.createdAt
        let rhsDate = rhs.startTime ?? rhs.endTime ?? rhs.createdAt
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func endCandidate(for entry: LogEntry) -> Candidate? {
        guard let date = entry.endTime else { return nil }
        return switch entry.kind {
        case .placeVisit:
            candidate(
                place: entry.placeVisitDetails?.place,
                location: entry.placeVisitDetails?.location,
                date: date
            )
        case .transit:
            candidate(
                place: entry.transitDetails?.destinationPlace,
                location: entry.transitDetails?.destinationLocation,
                date: date
            )
        case .workout, .wakeUp:
            nil
        }
    }

    private static func startCandidate(for entry: LogEntry) -> Candidate? {
        guard let date = entry.startTime else { return nil }
        return switch entry.kind {
        case .placeVisit:
            candidate(
                place: entry.placeVisitDetails?.place,
                location: entry.placeVisitDetails?.location,
                date: date
            )
        case .transit:
            candidate(
                place: entry.transitDetails?.originPlace,
                location: entry.transitDetails?.originLocation,
                date: date
            )
        case .workout, .wakeUp:
            nil
        }
    }

    private static func candidate(
        place: Place?,
        location: Location?,
        date: Date
    ) -> Candidate? {
        guard let place else { return nil }
        return Candidate(
            place: place,
            location: location ?? place.location,
            date: date
        )
    }

    private static func isCloseInTime(_ earlier: Date, _ later: Date) -> Bool {
        let delta = later.timeIntervalSince(earlier)
        return delta >= 0 && delta <= maximumTimeDelta
    }

    private static func isCloseInSpace(
        _ endpoint: Location,
        _ candidate: Location
    ) -> Bool {
        CLLocation(
            latitude: endpoint.latitude,
            longitude: endpoint.longitude
        ).distance(
            from: CLLocation(
                latitude: candidate.latitude,
                longitude: candidate.longitude
            )
        ) <= maximumEndpointDistanceMeters
    }

    private static func associate(
        _ place: Place,
        with field: WorkoutReviewField,
        in details: WorkoutDetails
    ) -> Bool {
        var changed = false
        switch field {
        case .origin:
            if details.originPlace?.id != place.id {
                details.originPlace = place
                changed = true
            }
        case .destination:
            if details.destinationPlace?.id != place.id {
                details.destinationPlace = place
                changed = true
            }
        case .place:
            return false
        }

        let previousReviewCount = details.fieldReviews.count
        details.fieldReviews.removeAll { $0.field == field }
        return changed || details.fieldReviews.count != previousReviewCount
    }

    private struct Candidate {
        let place: Place
        let location: Location
        let date: Date
    }
}
