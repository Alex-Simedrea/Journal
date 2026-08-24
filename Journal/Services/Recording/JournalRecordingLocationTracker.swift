import CoreLocation
import Foundation

enum JournalRecordingTrackerStartup: Sendable, Equatable {
    case established
    case unconfirmed
    case requiresForeground
    case authorizationDenied
}

@MainActor
final class JournalRecordingLocationTracker {
    private var task: Task<Void, Never>?
    private var startupContinuation: CheckedContinuation<
        JournalRecordingTrackerStartup,
        Never
    >?
    private var startupResolved = false
    private var generation = UUID()

    var isRunning: Bool { task != nil }

    func start(
        onLocation: @escaping @MainActor (CLLocation) async -> Void,
        onDiagnostic: @escaping @MainActor (String) async -> Void
    ) async -> JournalRecordingTrackerStartup {
        guard task == nil else { return .established }
        startupResolved = false
        let currentGeneration = UUID()
        generation = currentGeneration
        task = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self, !Task.isCancelled else { break }
                    if update.authorizationDenied
                        || update.authorizationDeniedGlobally
                        || update.authorizationRestricted {
                        resolveStartup(.authorizationDenied)
                        await onDiagnostic("authorization-denied")
                        continue
                    }
                    if update.insufficientlyInUse {
                        resolveStartup(.requiresForeground)
                        await onDiagnostic("insufficiently-in-use")
                        continue
                    }
                    if update.serviceSessionRequired {
                        await onDiagnostic("service-session-required")
                    }
                    if update.accuracyLimited {
                        await onDiagnostic("accuracy-limited")
                    }
                    guard let location = update.location else { continue }
                    resolveStartup(.established)
                    await onLocation(location)
                }
            } catch is CancellationError {
                // Expected when the user stops or a foreground retry restarts.
            } catch {
                await onDiagnostic("live-updates-error: \(error.localizedDescription)")
            }
            if self?.generation == currentGeneration {
                self?.task = nil
            }
        }

        return await withCheckedContinuation { continuation in
            startupContinuation = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.resolveStartup(.unconfirmed)
            }
        }
    }

    func stop() {
        generation = UUID()
        task?.cancel()
        task = nil
        resolveStartup(.unconfirmed)
    }

    private func resolveStartup(_ result: JournalRecordingTrackerStartup) {
        guard !startupResolved else { return }
        startupResolved = true
        startupContinuation?.resume(returning: result)
        startupContinuation = nil
    }
}
