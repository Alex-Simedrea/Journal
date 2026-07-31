import CoreLocation
import Foundation

enum GuidedComposerCurrentLocationStatus: Equatable {
    case idle
    case capturing
    case available
    case unavailable(String)

    var message: String? {
        guard case .unavailable(let message) = self else { return nil }
        return message
    }
}

@MainActor
final class GuidedComposerCurrentLocationCoordinator {
    struct Snapshot: Equatable {
        let location: Location
        let capturedAt: Date
    }

    typealias AuthorizationProvider = @MainActor () -> CLAuthorizationStatus
    typealias Capture = @MainActor () async throws -> Location
    typealias Clock = @MainActor () -> Date

    private let authorizationProvider: AuthorizationProvider
    private let capture: Capture
    private let clock: Clock
    private let timeToLive: TimeInterval

    private(set) var snapshot: Snapshot?
    private(set) var status: GuidedComposerCurrentLocationStatus = .idle
    private var captureTask: Task<Void, Never>?
    private var captureID = UUID()
    private var lastCaptureAttemptAt: Date?

    init(
        timeToLive: TimeInterval =
            GuidedComposerPolicy.currentLocationTimeToLive,
        authorizationProvider: @escaping AuthorizationProvider = {
            LocationService.shared.authorizationStatus
        },
        capture: @escaping Capture = {
            try await LocationService.shared.captureCurrentLocation()
        },
        clock: @escaping Clock = { .now }
    ) {
        self.timeToLive = timeToLive
        self.authorizationProvider = authorizationProvider
        self.capture = capture
        self.clock = clock
    }

    var freshLocation: Location? {
        guard let snapshot,
              clock().timeIntervalSince(snapshot.capturedAt) < timeToLive else {
            return nil
        }
        return snapshot.location
    }

    func update(
        isNeeded: Bool,
        isToday: Bool,
        onChange: @escaping @MainActor () -> Void
    ) {
        guard isToday else {
            let changed = snapshot != nil || status != .idle
            cancelAndClear()
            if changed {
                onChange()
            }
            return
        }
        guard isNeeded else {
            cancelCapture()
            if status == .capturing {
                status = .idle
                onChange()
            }
            return
        }
        guard freshLocation == nil else {
            if status != .available {
                status = .available
                onChange()
            }
            return
        }
        guard captureTask == nil else { return }
        if case .unavailable = status,
           let lastCaptureAttemptAt,
           clock().timeIntervalSince(lastCaptureAttemptAt)
               < GuidedComposerPolicy
                   .currentLocationFailureRetryInterval {
            return
        }

        switch authorizationProvider() {
        case .authorizedAlways, .authorizedWhenInUse, .notDetermined:
            beginCapture(onChange: onChange)
        case .denied, .restricted:
            setStatus(
                .unavailable(
                    LocationCaptureError.authorizationDenied
                        .localizedDescription
                ),
                onChange: onChange
            )
        @unknown default:
            setStatus(
                .unavailable(
                    String(localized: "Current location is unavailable.")
                ),
                onChange: onChange
            )
        }
    }

    func appBecameActive(
        isNeeded: Bool,
        isToday: Bool,
        onChange: @escaping @MainActor () -> Void
    ) {
        if freshLocation == nil, snapshot != nil {
            snapshot = nil
        }
        lastCaptureAttemptAt = nil
        update(
            isNeeded: isNeeded,
            isToday: isToday,
            onChange: onChange
        )
    }

    func cancelAndClear() {
        cancelCapture()
        snapshot = nil
        status = .idle
        lastCaptureAttemptAt = nil
    }

    private func beginCapture(
        onChange: @escaping @MainActor () -> Void
    ) {
        captureID = UUID()
        let requestID = captureID
        lastCaptureAttemptAt = clock()
        status = .capturing
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let location = try await capture()
                guard !Task.isCancelled, captureID == requestID else {
                    return
                }
                snapshot = Snapshot(
                    location: location,
                    capturedAt: clock()
                )
                status = .available
                captureTask = nil
                onChange()
            } catch is CancellationError {
                guard captureID == requestID else { return }
                captureTask = nil
            } catch {
                guard !Task.isCancelled, captureID == requestID else {
                    return
                }
                snapshot = nil
                status = .unavailable(error.localizedDescription)
                captureTask = nil
                onChange()
            }
        }
    }

    private func setStatus(
        _ newStatus: GuidedComposerCurrentLocationStatus,
        onChange: @escaping @MainActor () -> Void
    ) {
        guard status != newStatus else { return }
        status = newStatus
        onChange()
    }

    private func cancelCapture() {
        captureTask?.cancel()
        captureTask = nil
        captureID = UUID()
    }
}
