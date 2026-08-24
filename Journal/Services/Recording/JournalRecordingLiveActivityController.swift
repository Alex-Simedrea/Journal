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
        entry: LogEntry?
    ) async {
        let content = ActivityContent(
            state: completedState(
                for: recording,
                finalization: finalization,
                entry: entry
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
        entry: LogEntry?
    ) -> JournalRecordingActivityAttributes.ContentState {
        let summary = summary(finalization: finalization, entry: entry)
        return JournalRecordingActivityAttributes.ContentState(
            phase: .completed,
            distanceMeters: entry?.transitDetails?.distanceMeters
                ?? recording.approximateDistanceMeters,
            movementDescription: recording.currentMovement.activityDescription,
            needsForegroundLaunch: false,
            endedAt: recording.endedAt ?? .now,
            summaryTitle: summary.title,
            summaryDetail: summary.detail,
            showsDistance: entry?.kind == .transit
        )
    }

    private func summary(
        finalization: JournalRecordingFinalization,
        entry: LogEntry?
    ) -> (title: String, detail: String?) {
        switch finalization {
        case .visit:
            let details = entry?.placeVisitDetails
            let placeName = details?.place?.name
                ?? details?.location?.timelineName
            return (
                String(localized: "Place Visit"),
                placeName ?? String(localized: "Saved to Journal")
            )
        case .transit(let mode):
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
        case .noUsableLocation:
            return (
                String(localized: "Recording Finished"),
                String(localized: "No journal entry was created")
            )
        }
    }
}
