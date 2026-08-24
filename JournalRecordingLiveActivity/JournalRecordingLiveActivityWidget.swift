import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct JournalRecordingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(
            for: JournalRecordingActivityAttributes.self
        ) { context in
            JournalRecordingLockScreenView(
                startedAt: context.attributes.startedAt,
                state: context.state
            )
            .activityBackgroundTint(.black.opacity(0.82))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "attractivestar-journal://recording"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    JournalRecordingIslandLeadingView(
                        phase: context.state.phase
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    JournalRecordingIslandTrailingView(
                        startedAt: context.attributes.startedAt,
                        phase: context.state.phase
                    )
                }
                DynamicIslandExpandedRegion(.bottom) {
                    JournalRecordingIslandBottomView(
                        startedAt: context.attributes.startedAt,
                        state: context.state
                    )
                }
            } compactLeading: {
                JournalRecordingCompactIcon(phase: context.state.phase)
            } compactTrailing: {
                JournalRecordingCompactTrailingView(
                    startedAt: context.attributes.startedAt,
                    phase: context.state.phase
                )
            } minimal: {
                JournalRecordingCompactIcon(phase: context.state.phase)
            }
            .widgetURL(URL(string: "attractivestar-journal://recording"))
        }
    }
}

private struct JournalRecordingLockScreenView: View {
    let startedAt: Date
    let state: JournalRecordingActivityAttributes.ContentState

    var body: some View {
        Group {
            switch state.phase {
            case .recording:
                JournalRecordingActiveView(startedAt: startedAt, state: state)
            case .finalizing:
                JournalRecordingSavingView()
            case .completed:
                JournalRecordingSummaryView(startedAt: startedAt, state: state)
            }
        }
        .padding()
    }
}

private struct JournalRecordingActiveView: View {
    let startedAt: Date
    let state: JournalRecordingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                JournalRecordingActivityTitle()
                JournalRecordingMetricsView(
                    distanceMeters: state.distanceMeters,
                    movementDescription: state.movementDescription,
                    needsForegroundLaunch: state.needsForegroundLaunch
                )
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                Text(startedAt, style: .timer)
                    .font(.title2.monospacedDigit())
                JournalRecordingStopButton()
            }
        }
    }
}

private struct JournalRecordingActivityTitle: View {
    var body: some View {
        Label("Journal Recording", systemImage: "record.circle.fill")
            .font(.headline)
            .foregroundStyle(.primary)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .red)
    }
}

private struct JournalRecordingMetricsView: View {
    let distanceMeters: Double
    let movementDescription: String
    let needsForegroundLaunch: Bool

    var body: some View {
        if needsForegroundLaunch {
            Label("Open Journal to begin tracking", systemImage: "location.slash")
                .font(.caption)
                .foregroundStyle(.yellow)
        } else {
            HStack(spacing: 10) {
                Text(
                    Measurement(value: distanceMeters, unit: UnitLength.meters),
                    format: .measurement(width: .abbreviated, usage: .road)
                )
                Text(movementDescription)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct JournalRecordingStopButton: View {
    var body: some View {
        Button(intent: StopJournalRecordingIntent()) {
            Label("Stop", systemImage: "stop.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .font(.caption.weight(.semibold))
    }
}

private struct JournalRecordingSavingView: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 3) {
                Text("Saving Recording…")
                    .font(.headline)
                Text("Creating your journal entry")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct JournalRecordingSummaryView: View {
    let startedAt: Date
    let state: JournalRecordingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                if let title = state.summaryTitle {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    Text("Recording Saved")
                        .font(.headline)
                }
                if let detail = state.summaryDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let endedAt = state.endedAt {
                    JournalRecordingTimeRangeView(
                        startedAt: startedAt,
                        endedAt: endedAt
                    )
                }
                if state.showsDistance {
                    JournalRecordingDistanceView(
                        distanceMeters: state.distanceMeters
                    )
                }
            }
        }
    }
}

private struct JournalRecordingTimeRangeView: View {
    let startedAt: Date
    let endedAt: Date

    var body: some View {
        HStack(spacing: 2) {
            Text(startedAt, format: .dateTime.hour().minute())
            Text("–")
            Text(endedAt, format: .dateTime.hour().minute())
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

private struct JournalRecordingDistanceView: View {
    let distanceMeters: Double

    var body: some View {
        Text(
            Measurement(value: distanceMeters, unit: UnitLength.meters),
            format: .measurement(width: .abbreviated, usage: .road)
        )
        .font(.caption.weight(.medium))
    }
}

private struct JournalRecordingIslandLeadingView: View {
    let phase: JournalRecordingActivityPhase

    var body: some View {
        switch phase {
        case .recording:
            Label("Recording", systemImage: "record.circle.fill")
                .foregroundStyle(.red)
        case .finalizing:
            Label("Saving", systemImage: "hourglass")
                .foregroundStyle(.yellow)
        case .completed:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

private struct JournalRecordingIslandTrailingView: View {
    let startedAt: Date
    let phase: JournalRecordingActivityPhase

    var body: some View {
        if phase == .recording {
            Text(startedAt, style: .timer)
                .monospacedDigit()
        } else if phase == .finalizing {
            ProgressView()
        } else {
            Image(systemName: "checkmark")
                .foregroundStyle(.green)
        }
    }
}

private struct JournalRecordingIslandBottomView: View {
    let startedAt: Date
    let state: JournalRecordingActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .recording:
            HStack(spacing: 12) {
                JournalRecordingMetricsView(
                    distanceMeters: state.distanceMeters,
                    movementDescription: state.movementDescription,
                    needsForegroundLaunch: state.needsForegroundLaunch
                )
                Spacer(minLength: 4)
                JournalRecordingStopButton()
            }
        case .finalizing:
            Text("Creating your journal entry…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .completed:
            JournalRecordingSummaryView(startedAt: startedAt, state: state)
        }
    }
}

private struct JournalRecordingCompactIcon: View {
    let phase: JournalRecordingActivityPhase

    var body: some View {
        switch phase {
        case .recording:
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.red)
        case .finalizing:
            Image(systemName: "hourglass")
                .foregroundStyle(.yellow)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

private struct JournalRecordingCompactTrailingView: View {
    let startedAt: Date
    let phase: JournalRecordingActivityPhase

    var body: some View {
        if phase == .recording {
            Text(startedAt, style: .timer)
                .monospacedDigit()
                .frame(maxWidth: 52)
        } else if phase == .finalizing {
            Text("Saving")
                .font(.caption2)
        } else {
            Text("Saved")
                .font(.caption2)
        }
    }
}
