import Foundation

@MainActor
final class GuidedComposerRouteDurationCache {
    typealias Request = @MainActor (
        _ origin: Location,
        _ destination: Location,
        _ routingMode: TransitRoutingMode
    ) async throws -> TimeInterval

    private var values: [Key: TimeInterval] = [:]
    private var inFlight: [Key: InFlightRequest] = [:]
    private let request: Request

    init(
        request: @escaping Request = { origin, destination, routingMode in
            try await TransitMapKitService.estimatedTravelTime(
                from: origin.coordinate,
                to: destination.coordinate,
                routingMode: routingMode
            )
        }
    ) {
        self.request = request
    }

    func duration(
        from origin: ComposerLocationCandidate,
        to destination: ComposerLocationCandidate,
        routingMode: TransitRoutingMode
    ) async -> TimeInterval? {
        let key = Key(
            origin: origin.location,
            destination: destination.location,
            routingMode: routingMode
        )
        if let cached = values[key] {
            return cached
        }
        let pending: InFlightRequest
        if let existing = inFlight[key] {
            pending = existing
        } else {
            let id = UUID()
            let originLocation = origin.location
            let destinationLocation = destination.location
            let request = request
            let task = Task {
                try? await request(
                    originLocation,
                    destinationLocation,
                    routingMode
                )
            }
            pending = InFlightRequest(id: id, task: task)
            inFlight[key] = pending
        }

        let duration = await pending.task.value
        if inFlight[key]?.id == pending.id {
            inFlight[key] = nil
            if let duration {
                values[key] = duration
            }
        }
        guard !Task.isCancelled else { return nil }
        return duration
    }

    private struct InFlightRequest {
        let id: UUID
        let task: Task<TimeInterval?, Never>
    }

    private struct Key: Hashable {
        let originLatitude: Int
        let originLongitude: Int
        let destinationLatitude: Int
        let destinationLongitude: Int
        let routingMode: TransitRoutingMode

        init(
            origin: Location,
            destination: Location,
            routingMode: TransitRoutingMode
        ) {
            originLatitude = Self.quantized(origin.latitude)
            originLongitude = Self.quantized(origin.longitude)
            destinationLatitude = Self.quantized(destination.latitude)
            destinationLongitude = Self.quantized(destination.longitude)
            self.routingMode = routingMode
        }

        private static func quantized(_ value: Double) -> Int {
            Int((value * 100_000).rounded())
        }
    }
}
