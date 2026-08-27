import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct JournalRecordingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(
            for: JournalRecordingActivityAttributes.self
        ) { context in
            JournalRecordingActivityContent(
                startedAt: context.attributes.startedAt,
                state: context.state
            )
            .activityBackgroundTint(nil)
            .activitySystemActionForegroundColor(.orange)
            .widgetURL(URL(string: "attractivestar-journal://recording"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    JournalRecordingIslandLeadingView(
                        startedAt: context.attributes.startedAt,
                        phase: context.state.phase,
                        distanceMeters: context.state.distanceMeters,
                        movementDescription: context.state.movementDescription,
                        needsForegroundLaunch: context.state
                            .needsForegroundLaunch
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    JournalRecordingIslandTrailingView(
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
                    .padding(.leading, 4)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                JournalRecordingCompactIcon(phase: context.state.phase)
            }
            .widgetURL(URL(string: "attractivestar-journal://recording"))
        }
        .supplementalActivityFamilies([.small])
    }
}

private struct JournalRecordingActivityContent: View {
    @Environment(\.activityFamily) private var activityFamily

    let startedAt: Date
    let state: JournalRecordingActivityAttributes.ContentState

    var body: some View {
        switch activityFamily {
        case .small:
            JournalRecordingWatchView(startedAt: startedAt, state: state)
                .padding(.horizontal, 8)
        case .medium:
            JournalRecordingLockScreenView(startedAt: startedAt, state: state)
        @unknown default:
            JournalRecordingLockScreenView(startedAt: startedAt, state: state)
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
                JournalRecordingActiveView(
                    startedAt: startedAt,
                    distanceMeters: state.distanceMeters,
                    movementDescription: state.movementDescription,
                    needsForegroundLaunch: state.needsForegroundLaunch
                )
            case .finalizing:
                JournalRecordingSavingView()
            case .completed:
                JournalRecordingSummaryView(startedAt: startedAt, state: state)
            }
        }
        .padding()
    }
}

private struct JournalRecordingWatchView: View {
    let startedAt: Date
    let state: JournalRecordingActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .recording:
            JournalRecordingWatchActiveView(
                startedAt: startedAt,
                distanceMeters: state.distanceMeters,
                movementDescription: state.movementDescription,
                needsForegroundLaunch: state.needsForegroundLaunch
            )
        case .finalizing:
            JournalRecordingWatchSavingView()
        case .completed:
            JournalRecordingWatchSummaryView(
                startedAt: startedAt,
                endedAt: state.endedAt,
                title: state.summaryTitle,
                detail: state.summaryDetail,
                distanceMeters: state.distanceMeters,
                showsDistance: state.showsDistance
            )
        }
    }
}

private struct JournalRecordingWatchActiveView: View {
    let startedAt: Date
    let distanceMeters: Double
    let movementDescription: String
    let needsForegroundLaunch: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(startedAt, style: .timer)
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                JournalRecordingWatchMetricsView(
                    distanceMeters: distanceMeters,
                    movementDescription: movementDescription,
                    needsForegroundLaunch: needsForegroundLaunch
                )
            }
            Spacer(minLength: 2)
            JournalRecordingStopButton(diameter: 42)
        }
    }
}

private struct JournalRecordingWatchMetricsView: View {
    let distanceMeters: Double
    let movementDescription: String
    let needsForegroundLaunch: Bool

    var body: some View {
        if needsForegroundLaunch {
            Label("Open iPhone to track", systemImage: "iphone")
                .font(.caption2)
                .foregroundStyle(.yellow)
                .lineLimit(1)
        } else {
            HStack(spacing: 3) {
                Text(
                    Measurement(
                        value: distanceMeters,
                        unit: UnitLength.meters
                    ),
                    format: .measurement(
                        width: .abbreviated,
                        usage: .road
                    )
                )
                Text("•")
                Text(movementDescription)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}

private struct JournalRecordingWatchSavingView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.headline)
                .foregroundStyle(.orange)
                .frame(width: 34, height: 34)
                .background(.orange.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("Saving Recording…")
                    .font(.headline)
                    .lineLimit(1)
                Text("Creating your journal entry")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct JournalRecordingWatchSummaryView: View {
    let startedAt: Date
    let endedAt: Date?
    let title: String?
    let detail: String?
    let distanceMeters: Double
    let showsDistance: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                if let title {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    Text("Recording Saved")
                        .font(.headline)
                        .lineLimit(1)
                }
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                JournalRecordingWatchSummaryMetadata(
                    startedAt: startedAt,
                    endedAt: endedAt,
                    distanceMeters: distanceMeters,
                    showsDistance: showsDistance
                )
            }
            Spacer(minLength: 0)
        }
    }
}

private struct JournalRecordingWatchSummaryMetadata: View {
    let startedAt: Date
    let endedAt: Date?
    let distanceMeters: Double
    let showsDistance: Bool

    var body: some View {
        HStack(spacing: 3) {
            if let endedAt {
                Text(startedAt, format: .dateTime.hour().minute())
                Text("–")
                Text(endedAt, format: .dateTime.hour().minute())
            }
            if endedAt != nil, showsDistance {
                Text("•")
            }
            if showsDistance {
                Text(
                    Measurement(
                        value: distanceMeters,
                        unit: UnitLength.meters
                    ),
                    format: .measurement(
                        width: .abbreviated,
                        usage: .road
                    )
                )
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct JournalRecordingActiveView: View {
    let startedAt: Date
    let distanceMeters: Double
    let movementDescription: String
    let needsForegroundLaunch: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                JournalRecordingMetricsView(
                    distanceMeters: distanceMeters,
                    movementDescription: movementDescription,
                    needsForegroundLaunch: needsForegroundLaunch
                )
                Text(startedAt, style: .timer)
                    .font(.title.monospacedDigit().weight(.medium))
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 8)
            JournalRecordingStopButton(diameter: 58)
        }
    }
}

private struct JournalRecordingMetricsView: View {
    let distanceMeters: Double
    let movementDescription: String
    let needsForegroundLaunch: Bool

    var body: some View {
        if needsForegroundLaunch {
            Label(
                "Open Journal to begin tracking",
                systemImage: "location.slash"
            )
            .font(.caption)
            .foregroundStyle(.yellow)
        } else {
            HStack(spacing: 0) {
                Text(
                    Measurement(value: distanceMeters, unit: UnitLength.meters),
                    format: .measurement(width: .abbreviated, usage: .road)
                )
                Text(" • " + movementDescription)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
    }
}

private struct JournalRecordingStopButton: View {
    let diameter: CGFloat

    var body: some View {
        Button(intent: StopJournalRecordingIntent()) {
            Image(systemName: "stop.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(.orange)
                .frame(width: diameter, height: diameter)
                .background(.orange.opacity(0.22), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop Recording")
    }
}

private struct JournalRecordingSavingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Saving Recording…")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Creating your journal entry")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct JournalRecordingSummaryView: View {
    let startedAt: Date
    let state: JournalRecordingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 0) {
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
    let startedAt: Date
    let phase: JournalRecordingActivityPhase
    let distanceMeters: Double
    let movementDescription: String
    let needsForegroundLaunch: Bool

    var body: some View {
        switch phase {
        case .recording:
            VStack(alignment: .leading, spacing: 0) {
                JournalRecordingMetricsView(
                    distanceMeters: distanceMeters,
                    movementDescription: movementDescription,
                    needsForegroundLaunch: needsForegroundLaunch
                )
                Text(startedAt, style: .timer)
                    .font(.title.monospacedDigit().weight(.medium))
                    .foregroundStyle(.orange)
            }
            .padding(.leading, 8)
        case .finalizing:
            EmptyView()
        case .completed:
            EmptyView()
        }
    }
}

private struct JournalRecordingIslandTrailingView: View {
    let phase: JournalRecordingActivityPhase

    var body: some View {
        switch phase {
        case .recording:
            JournalRecordingStopButton(diameter: 46)
        case .finalizing, .completed:
            EmptyView()
        }
    }
}

private struct JournalRecordingIslandBottomView: View {
    let startedAt: Date
    let state: JournalRecordingActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .recording:
            EmptyView()
        case .finalizing:
            Text("Saving…")
                .font(.title2.weight(.medium))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                .foregroundStyle(.orange)
        case .finalizing:
            Image(systemName: "hourglass")
                .foregroundStyle(.yellow)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

#if DEBUG
    extension JournalRecordingActivityAttributes {
        fileprivate nonisolated static var preview: Self {
            JournalRecordingActivityAttributes(
                sessionID: UUID(
                    uuidString: "68C913F1-54BA-4CB1-853D-D73A1F2D56C2"
                )!,
                startedAt: .now.addingTimeInterval(-23 * 60)
            )
        }
    }

    extension JournalRecordingActivityAttributes.ContentState {
        fileprivate nonisolated static var recordingPreview: Self {
            JournalRecordingActivityAttributes.ContentState(
                phase: .recording,
                distanceMeters: 2_400,
                movementDescription: "Walking",
                needsForegroundLaunch: false,
                endedAt: nil,
                summaryTitle: nil,
                summaryDetail: nil,
                showsDistance: true
            )
        }

        fileprivate nonisolated static var savingPreview: Self {
            JournalRecordingActivityAttributes.ContentState(
                phase: .finalizing,
                distanceMeters: 2_400,
                movementDescription: "Walking",
                needsForegroundLaunch: false,
                endedAt: nil,
                summaryTitle: nil,
                summaryDetail: nil,
                showsDistance: true
            )
        }

        fileprivate nonisolated static var visitPreview: Self {
            JournalRecordingActivityAttributes.ContentState(
                phase: .completed,
                distanceMeters: 24,
                movementDescription: "Stationary",
                needsForegroundLaunch: false,
                endedAt: .now,
                summaryTitle: "Place Visit",
                summaryDetail: "Romanian Athenaeum",
                showsDistance: false
            )
        }

        fileprivate nonisolated static var transitPreview: Self {
            JournalRecordingActivityAttributes.ContentState(
                phase: .completed,
                distanceMeters: 5_200,
                movementDescription: "Walking",
                needsForegroundLaunch: false,
                endedAt: .now,
                summaryTitle: "Walk",
                summaryDetail: "Home → Romanian Athenaeum",
                showsDistance: true
            )
        }
    }

    private struct JournalRecordingWatchPreviewSurface: View {
        let state: JournalRecordingActivityAttributes.ContentState

        var body: some View {
            JournalRecordingWatchView(
                startedAt: JournalRecordingActivityAttributes.preview.startedAt,
                state: state
            )
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Color.clear
                    .glassEffect(
                        .regular.tint(.black.opacity(0.42)),
                        in: ContainerRelativeShape()
                    )
            }
            .preferredColorScheme(.dark)
        }
    }

    #Preview(
        "Apple Watch · Recording",
        traits: .fixedLayout(width: 180, height: 82)
    ) {
        JournalRecordingWatchPreviewSurface(state: .recordingPreview)
    }

    #Preview(
        "Apple Watch · Saving",
        traits: .fixedLayout(width: 180, height: 82)
    ) {
        JournalRecordingWatchPreviewSurface(state: .savingPreview)
    }

    #Preview(
        "Apple Watch · Saved",
        traits: .fixedLayout(width: 180, height: 82)
    ) {
        JournalRecordingWatchPreviewSurface(state: .transitPreview)
    }

    #Preview(
        "Lock Screen",
        as: .content,
        using: JournalRecordingActivityAttributes.preview
    ) {
        JournalRecordingLiveActivityWidget()
    } contentStates: {
        JournalRecordingActivityAttributes.ContentState.recordingPreview
        JournalRecordingActivityAttributes.ContentState.savingPreview
        JournalRecordingActivityAttributes.ContentState.visitPreview
        JournalRecordingActivityAttributes.ContentState.transitPreview
    }

    #Preview(
        "Dynamic Island · Expanded",
        as: .dynamicIsland(.expanded),
        using: JournalRecordingActivityAttributes.preview
    ) {
        JournalRecordingLiveActivityWidget()
    } contentStates: {
        JournalRecordingActivityAttributes.ContentState.recordingPreview
        JournalRecordingActivityAttributes.ContentState.savingPreview
        JournalRecordingActivityAttributes.ContentState.visitPreview
        JournalRecordingActivityAttributes.ContentState.transitPreview
    }

    #Preview(
        "Dynamic Island · Compact",
        as: .dynamicIsland(.compact),
        using: JournalRecordingActivityAttributes.preview
    ) {
        JournalRecordingLiveActivityWidget()
    } contentStates: {
        JournalRecordingActivityAttributes.ContentState.recordingPreview
        JournalRecordingActivityAttributes.ContentState.savingPreview
        JournalRecordingActivityAttributes.ContentState.visitPreview
    }

    #Preview(
        "Dynamic Island · Minimal",
        as: .dynamicIsland(.minimal),
        using: JournalRecordingActivityAttributes.preview
    ) {
        JournalRecordingLiveActivityWidget()
    } contentStates: {
        JournalRecordingActivityAttributes.ContentState.recordingPreview
        JournalRecordingActivityAttributes.ContentState.savingPreview
        JournalRecordingActivityAttributes.ContentState.visitPreview
    }
#endif
