import ActivityKit
import Foundation

@MainActor
final class JournalRecordingLiveActivityController {
    static let completedActivityRetention: TimeInterval = 2 * 60

    func start(for recording: ActiveJournalRecording) throws -> String? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return nil
        }
        if let existing = activity(for: recording.id) {
            return existing.id
        }
        let content = ActivityContent(
            state: state(for: recording),
            staleDate: nil
        )
        let activity = try Activity<JournalRecordingActivityAttributes>.request(
            attributes: JournalRecordingActivityAttributes(
                sessionID: recording.id,
                startedAt: recording.startedAt
            ),
            content: content,
            pushType: nil
        )
        return activity.id
    }

    func update(for recording: ActiveJournalRecording) async {
        guard let activity = activity(for: recording.id) else { return }
        await activity.update(
            ActivityContent(state: state(for: recording), staleDate: nil)
        )
    }

    func complete(
        for recording: ActiveJournalRecording,
        finalization: JournalRecordingFinalization,
        entries: [LogEntry]
    ) async {
        let content = ActivityContent(
            state: completedState(
                for: recording,
                finalization: finalization,
                entries: entries
            ),
            staleDate: nil
        )
        let dismissalDate = Date.now.addingTimeInterval(
            Self.completedActivityRetention
        )
        for activity in Activity<JournalRecordingActivityAttributes>.activities
        where activity.attributes.sessionID == recording.id {
            await activity.end(
                content,
                dismissalPolicy: .after(dismissalDate)
            )
        }
    }

    private func activity(
        for sessionID: UUID
    ) -> Activity<JournalRecordingActivityAttributes>? {
        Activity<JournalRecordingActivityAttributes>.activities.first {
            $0.attributes.sessionID == sessionID
        }
    }

    private func state(
        for recording: ActiveJournalRecording
    ) -> JournalRecordingActivityAttributes.ContentState {
        JournalRecordingActivityAttributes.ContentState(
            phase: recording.status == .stopping
                ? .finalizing
                : .recording,
            distanceMeters: recording.approximateDistanceMeters,
            movementDescription: recording.currentMovement.activityDescription,
            needsForegroundLaunch: recording.status == .awaitingForeground,
            endedAt: nil,
            summaryTitle: nil,
            summaryDetail: nil,
            showsDistance: true
        )
    }

    private func completedState(
        for recording: ActiveJournalRecording,
        finalization: JournalRecordingFinalization,
        entries: [LogEntry]
    ) -> JournalRecordingActivityAttributes.ContentState {
        let summary = summary(finalization: finalization, entries: entries)
        let transitDistance = entries.reduce(0.0) { result, entry in
            result + (entry.transitDetails?.distanceMeters ?? 0)
        }
        return JournalRecordingActivityAttributes.ContentState(
            phase: .completed,
            distanceMeters: transitDistance > 0
                ? transitDistance
                : recording.approximateDistanceMeters,
            movementDescription: recording.currentMovement.activityDescription,
            needsForegroundLaunch: false,
            endedAt: recording.endedAt ?? .now,
            summaryTitle: summary.title,
            summaryDetail: summary.detail,
            showsDistance: entries.contains { $0.kind == .transit }
        )
    }

    private func summary(
        finalization: JournalRecordingFinalization,
        entries: [LogEntry]
    ) -> (title: String, detail: String?) {
        switch finalization {
        case .visit:
            let entry = entries.first
            let details = entry?.placeVisitDetails
            let placeName = details?.place?.name
                ?? details?.location?.timelineName
            return (
                String(localized: "Place Visit"),
                placeName ?? String(localized: "Saved to Journal")
            )
        case .transit(let mode):
            let entry = entries.first
            let details = entry?.transitDetails
            let origin = details?.originPlace?.name
                ?? details?.originLocation?.timelineName
            let destination = details?.destinationPlace?.name
                ?? details?.destinationLocation?.timelineName
            let route = if let origin, let destination {
                "\(origin) → \(destination)"
            } else {
                String(localized: "Saved to Journal")
            }
            return (mode.transitTypeName, route)
        case .batch(let entryCount, let visitCount, let transitCount):
            let title = entryCount == 1
                ? String(localized: "1 Journal Entry Saved")
                : String(localized: "\(entryCount) Journal Entries Saved")
            let visits = visitCount == 1
                ? String(localized: "1 visit")
                : String(localized: "\(visitCount) visits")
            let transits = transitCount == 1
                ? String(localized: "1 transit")
                : String(localized: "\(transitCount) transits")
            return (
                title,
                String(localized: "\(visits) • \(transits)")
            )
        case .noUsableLocation:
            return (
                String(localized: "Recording Finished"),
                String(localized: "No journal entry was created")
            )
        }
    }
}
