import CoreLocation
import Foundation
import OSLog
import SwiftData
import UIKit

nonisolated enum JournalRecordingToggleOrigin: Sendable, Equatable {
    case backgroundIntent
    case foregroundIntent
}

nonisolated enum JournalRecordingToggleResult: Sendable, Equatable {
    case started
    case stopped(JournalRecordingFinalization)
    case needsForeground
    case transitionInProgress
}

nonisolated enum JournalRecordingTransitionAction: Equatable {
    case start
    case stop
    case resumeInForeground
    case needsForeground
    case wait
}

nonisolated enum JournalRecordingStateMachine {
    static func action(
        for status: JournalRecordingStatus?,
        origin: JournalRecordingToggleOrigin
    ) -> JournalRecordingTransitionAction {
        guard let status else { return .start }
        switch status {
        case .recording: return .stop
        case .awaitingForeground:
            return origin == .backgroundIntent
                ? .needsForeground
                : .resumeInForeground
        case .starting, .stopping: return .wait
        }
    }
}

nonisolated enum JournalRecordingTrackingConfiguration {
    static let maximumHorizontalAccuracy = 150.0
    static let minimumStationaryPersistenceInterval: TimeInterval = 60
    static let minimumFastSampleInterval: TimeInterval = 5
    static let minimumFastSampleDistance = 50.0
    static let stationaryDistance = 10.0
    static let liveActivityDistanceStep = 100.0
}

nonisolated enum JournalRecordingLog {
    static let recording = Logger(subsystem: "ro.attractivestar.Journal", category: "Recording")
    static let location = Logger(subsystem: "ro.attractivestar.Journal", category: "Location")
    static let motion = Logger(subsystem: "ro.attractivestar.Journal", category: "Motion")
    static let classifier = Logger(subsystem: "ro.attractivestar.Journal", category: "Classifier")
}

@MainActor
final class JournalRecordingCoordinator {
    static let shared = JournalRecordingCoordinator()

    private let tracker = JournalRecordingLocationTracker()
    private let liveActivity = JournalRecordingLiveActivityController()
    private let finalizer = JournalRecordingFinalizer()
    private var backgroundActivitySession: CLBackgroundActivitySession?

    private init() {}

    func toggle(
        origin: JournalRecordingToggleOrigin,
        mode: JournalRecordingMode = .singleEntry
    ) async throws -> JournalRecordingToggleResult {
        let context = ModelContext(JournalModelContainer.shared)
        let recording = try activeRecording(in: context)
        if let recording {
            JournalRecordingLog.recording.info(
                "[Recording] existing state: \(recording.status.rawValue)"
            )
        }
        switch JournalRecordingStateMachine.action(
            for: recording?.status,
            origin: origin
        ) {
        case .start:
            return try await start(origin: origin, mode: mode, in: context)
        case .stop:
            if let recording {
                return try await stop(recording, in: context)
            }
        case .resumeInForeground:
            if let recording {
                return try await resumeInForeground(recording, in: context)
            }
        case .needsForeground:
            return .needsForeground
        case .wait:
            return .transitionInProgress
        }
        return .transitionInProgress
    }

    func restoreIfNeeded(applicationIsActive: Bool) {
        let context = ModelContext(JournalModelContainer.shared)
        guard let recording = try? activeRecording(in: context) else { return }
        JournalRecordingLog.recording.info(
            "[Recording] app restored with active session \(recording.id) in state \(recording.status.rawValue)"
        )
        if recording.status == .stopping {
            Task { [weak self] in
                _ = try? await self?.finishStopping(recording, in: context)
            }
            return
        }
        if recording.startPath == .foregroundFallback {
            // Recreates an already-established session immediately on relaunch.
            backgroundActivitySession = CLBackgroundActivitySession()
        }
        if applicationIsActive, recording.status == .awaitingForeground {
            Task { [weak self] in
                _ = try? await self?.resumeInForeground(recording, in: context)
            }
        } else {
            startTracking(recording, in: context)
            restoreLiveActivity(recording, in: context)
        }
    }

    func appDidBecomeActive() {
        let context = ModelContext(JournalModelContainer.shared)
        guard let recording = try? activeRecording(in: context),
              recording.status == .awaitingForeground else { return }
        Task { [weak self] in
            _ = try? await self?.resumeInForeground(recording, in: context)
        }
    }

    func stopFromLiveActivity() async throws {
        let context = ModelContext(JournalModelContainer.shared)
        guard let recording = try activeRecording(in: context) else { return }
        switch recording.status {
        case .recording, .awaitingForeground:
            _ = try await stop(recording, in: context)
        case .starting, .stopping:
            return
        }
    }

    private func start(
        origin: JournalRecordingToggleOrigin,
        mode: JournalRecordingMode,
        in context: ModelContext
    ) async throws -> JournalRecordingToggleResult {
        let path: JournalRecordingStartPath = origin == .backgroundIntent
            ? .backgroundIntent
            : .foregroundFallback
        let recording = ActiveJournalRecording(startPath: path, mode: mode)
        context.insert(recording)
        try context.save()
        JournalRecordingLog.recording.info(
            "[Recording] started session \(recording.id) via \(path.rawValue)"
        )

        if origin != .backgroundIntent {
            backgroundActivitySession = CLBackgroundActivitySession()
        }
        do {
            recording.activityID = try liveActivity.start(for: recording)
            try context.save()
            JournalRecordingLog.recording.info("[Recording] Live Activity started")
        } catch {
            recording.lastDiagnostic = "live-activity-error: \(error.localizedDescription)"
            try context.save()
            JournalRecordingLog.recording.error(
                "[Recording] Live Activity failed: \(error.localizedDescription)"
            )
        }

        let startup = await beginTracking(recording, in: context)
        switch startup {
        case .requiresForeground, .authorizationDenied:
            recording.status = .awaitingForeground
            recording.lastUpdatedAt = .now
            try context.save()
            await liveActivity.update(for: recording)
            return .needsForeground
        case .established, .unconfirmed:
            recording.status = .recording
            recording.lastUpdatedAt = .now
            try context.save()
            return .started
        }
    }

    private func resumeInForeground(
        _ recording: ActiveJournalRecording,
        in context: ModelContext
    ) async throws -> JournalRecordingToggleResult {
        tracker.stop()
        backgroundActivitySession?.invalidate()
        backgroundActivitySession = CLBackgroundActivitySession()
        recording.status = .starting
        recording.startPath = .foregroundFallback
        recording.lastDiagnostic = nil
        recording.lastUpdatedAt = .now
        try context.save()

        let startup = await beginTracking(recording, in: context)
        recording.status = switch startup {
        case .authorizationDenied, .requiresForeground: .awaitingForeground
        case .established, .unconfirmed: .recording
        }
        recording.lastUpdatedAt = .now
        try context.save()
        await liveActivity.update(for: recording)
        return recording.status == .recording ? .started : .needsForeground
    }

    private func stop(
        _ recording: ActiveJournalRecording,
        in context: ModelContext
    ) async throws -> JournalRecordingToggleResult {
        recording.status = .stopping
        recording.endedAt = .now
        recording.lastUpdatedAt = .now
        try context.save()
        JournalRecordingLog.recording.info(
            "[Recording] stopping session \(recording.id)"
        )
        return try await finishStopping(recording, in: context)
    }

    private func finishStopping(
        _ recording: ActiveJournalRecording,
        in context: ModelContext
    ) async throws -> JournalRecordingToggleResult {
        tracker.stop()
        backgroundActivitySession?.invalidate()
        backgroundActivitySession = nil
        await liveActivity.update(for: recording)
        let result = try await finalizer.finalize(recording, in: context)
        let entries = try finalizedEntries(for: recording.id, in: context)
        await liveActivity.complete(
            for: recording,
            finalization: result,
            entries: entries
        )
        context.delete(recording)
        try context.save()
        JournalRecordingLog.recording.info(
            "[Recording] finalized session \(recording.id)"
        )
        return .stopped(result)
    }

    private func beginTracking(
        _ recording: ActiveJournalRecording,
        in context: ModelContext
    ) async -> JournalRecordingTrackerStartup {
        JournalRecordingLog.location.info("[Location] liveUpdates sequence started")
        return await tracker.start(
            onLocation: { [weak self] location in
                await self?.receive(location, for: recording, in: context)
            },
            onDiagnostic: { [weak self] diagnostic in
                await self?.receiveDiagnostic(
                    diagnostic,
                    for: recording,
                    in: context
                )
            }
        )
    }

    private func startTracking(
        _ recording: ActiveJournalRecording,
        in context: ModelContext
    ) {
        guard !tracker.isRunning else { return }
        Task { [weak self] in
            guard let self else { return }
            let startup = await beginTracking(recording, in: context)
            if startup == .requiresForeground
                || startup == .authorizationDenied {
                recording.status = .awaitingForeground
                recording.lastUpdatedAt = .now
                try? context.save()
                await liveActivity.update(for: recording)
            } else if recording.status == .starting {
                recording.status = .recording
                try? context.save()
            }
        }
    }

    private func restoreLiveActivity(
        _ recording: ActiveJournalRecording,
        in context: ModelContext
    ) {
        do {
            recording.activityID = try liveActivity.start(for: recording)
            try context.save()
        } catch {
            JournalRecordingLog.recording.error(
                "[Recording] unable to restore Live Activity: \(error.localizedDescription)"
            )
        }
    }

    private func receive(
        _ location: CLLocation,
        for recording: ActiveJournalRecording,
        in context: ModelContext
    ) async {
        guard recording.status != .stopping,
              CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy
                <= JournalRecordingTrackingConfiguration
                    .maximumHorizontalAccuracy,
              location.timestamp >= recording.startedAt.addingTimeInterval(-30),
              location.timestamp <= .now.addingTimeInterval(10) else { return }

        let point = TrackedLocationPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy,
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            speed: location.speed >= 0 ? location.speed : nil,
            course: location.course >= 0 ? location.course : nil
        )
        let previousDistance = recording.approximateDistanceMeters
        if let previous = recording.points.last {
            let interval = point.timestamp.timeIntervalSince(previous.timestamp)
            let separation = CLLocation(
                latitude: previous.latitude,
                longitude: previous.longitude
            ).distance(from: location)
            if separation
                < JournalRecordingTrackingConfiguration.stationaryDistance,
               interval
                < JournalRecordingTrackingConfiguration
                    .minimumStationaryPersistenceInterval {
                return
            }
            if separation
                < JournalRecordingTrackingConfiguration
                    .minimumFastSampleDistance,
               interval
                < JournalRecordingTrackingConfiguration
                    .minimumFastSampleInterval {
                return
            }
        }
        let previousMovement = recording.currentMovement
        recording.points.append(point)
        let routeDistance = JournalRecordingClassifier.routeDistance(
            recording.points
        )
        let dwellFraction = JournalRecordingClassifier.dominantDwellFraction(
            recording.points
        )
        recording.approximateDistanceMeters = dwellFraction >= 0.9
            ? 0
            : routeDistance
        let confirmedDistanceDelta = recording.approximateDistanceMeters
            - previousDistance
        recording.currentMovement = confirmedDistanceDelta > 5
            ? movementHint(for: point.speed)
            : .unknown
        recording.status = .recording
        recording.lastUpdatedAt = .now
        do {
            try context.save()
            JournalRecordingLog.location.debug(
                "[Location] received \(point.latitude), \(point.longitude), accuracy \(point.horizontalAccuracy)m"
            )
        } catch {
            JournalRecordingLog.location.error(
                "[Location] failed to persist point: \(error.localizedDescription)"
            )
        }
        if Int(
            recording.approximateDistanceMeters
                / JournalRecordingTrackingConfiguration.liveActivityDistanceStep
        ) != Int(
            previousDistance
                / JournalRecordingTrackingConfiguration.liveActivityDistanceStep
        )
            || recording.currentMovement != previousMovement {
            await liveActivity.update(for: recording)
        }
    }

    private func receiveDiagnostic(
        _ diagnostic: String,
        for recording: ActiveJournalRecording,
        in context: ModelContext
    ) async {
        recording.lastDiagnostic = diagnostic
        recording.lastUpdatedAt = .now
        if diagnostic == "insufficiently-in-use" {
            recording.status = .awaitingForeground
        }
        try? context.save()
        JournalRecordingLog.location.notice(
            "[Location] diagnostic: \(diagnostic)"
        )
        await liveActivity.update(for: recording)
    }

    private func movementHint(for speed: Double?) -> RecordedTransitMode {
        guard let speed else { return .unknown }
        if speed < 0.5 { return .unknown }
        if speed <= 2.7 { return .walking }
        if speed <= 10 { return .cycling }
        return .unknown
    }

    private func activeRecording(
        in context: ModelContext
    ) throws -> ActiveJournalRecording? {
        var descriptor = FetchDescriptor<ActiveJournalRecording>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func finalizedEntries(
        for recordingID: UUID,
        in context: ModelContext
    ) throws -> [LogEntry] {
        try context.fetch(
            FetchDescriptor<LogEntry>(
                predicate: #Predicate { entry in
                    entry.journalRecordingID == recordingID
                },
                sortBy: [SortDescriptor(\.startTime)]
            )
        )
    }
}
