import AppIntents
import Foundation
import OSLog

struct ToggleJournalRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Toggle Journal Recording"
    static let description = IntentDescription(
        "Starts a journal recording when none is active, or stops the active recording."
    )
    static let supportedModes: IntentModes = [
        .background,
        .foreground(.dynamic),
    ]

    func perform() async throws -> some IntentResult {
        JournalRecordingLog.recording.info("[Recording] intent invoked")
        let isBackground = systemContext.currentMode == .background
        let result = try await JournalRecordingCoordinator.shared.toggle(
            origin: isBackground ? .backgroundIntent : .foregroundIntent
        )
        if result == .needsForeground, isBackground {
            try await continueInForeground(
                alwaysConfirm: false
            )
            _ = try await JournalRecordingCoordinator.shared.toggle(
                origin: .foregroundIntent
            )
        }
        return .result()
    }
}

struct ToggleJournalRecordingInAppIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Toggle Journal Recording in App"
    static let description = IntentDescription(
        "Opens Journal before toggling recording. Use this if background start is unreliable on this device."
    )
    static let supportedModes: IntentModes = [.foreground(.immediate)]

    func perform() async throws -> some IntentResult {
        _ = try await JournalRecordingCoordinator.shared.toggle(
            origin: .foregroundIntent
        )
        return .result()
    }
}

struct JournalAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleJournalRecordingIntent(),
            phrases: [
                "Toggle recording in \(.applicationName)",
                "Start or stop \(.applicationName)",
            ],
            shortTitle: "Toggle Recording",
            systemImageName: "record.circle"
        )
        AppShortcut(
            intent: ToggleJournalRecordingInAppIntent(),
            phrases: [
                "Toggle recording in the \(.applicationName) app",
            ],
            shortTitle: "Toggle in App",
            systemImageName: "location.circle"
        )
    }
}
