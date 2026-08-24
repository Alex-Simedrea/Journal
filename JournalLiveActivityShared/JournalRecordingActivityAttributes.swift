import ActivityKit
import AppIntents
import Foundation

nonisolated enum JournalRecordingActivityPhase: String, Codable, Hashable {
    case recording
    case finalizing
    case completed
}

nonisolated struct JournalRecordingActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var phase: JournalRecordingActivityPhase
        var distanceMeters: Double
        var movementDescription: String
        var needsForegroundLaunch: Bool
        var endedAt: Date?
        var summaryTitle: String?
        var summaryDetail: String?
        var showsDistance: Bool
    }

    var sessionID: UUID
    var startedAt: Date
}

struct StopJournalRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Journal Recording"
    static let description = IntentDescription(
        "Stops and saves the active journal recording."
    )
    static let supportedModes: IntentModes = [.background]
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
#if JOURNAL_APP
        try await JournalRecordingCoordinator.shared.stopFromLiveActivity()
#endif
        return .result()
    }
}
