//
//  TimeEditor.swift
//  Journal
//

import SwiftUI

struct TimeEditorRouteRequest: Equatable {
    let origin: Location
    let destination: Location
    let routingMode: TransitRoutingMode
}

struct TimeDurationPreset: Identifiable, Equatable {
    let minutes: Int

    var id: Int { minutes }

    static let fixed = [5, 10, 15, 30, 60].map(TimeDurationPreset.init)

    var title: String {
        minutes == 60 ? "1 hr" : "\(minutes) min"
    }

    var duration: TimeInterval {
        TimeInterval(minutes * 60)
    }
}

struct EntryDetailTimeEditor: View {
    @Bindable var session: EntryDetailEditSession
    let mapKitRequest: TimeEditorRouteRequest?
    let showsMapKitPreset: Bool
    let linkedCount: Int
    let onEditLinks: () -> Void
    let onSelectTimeZone: (EntryTimeZoneEndpoint) -> Void

    var body: some View {
        VStack(spacing: 18) {
            EntryLinkDisclosureRow(
                linkedCount: linkedCount,
                onSelect: onEditLinks
            )

            TimeEditorSection(
                title: "Start",
                date: $session.startTime,
                timeZoneIdentifier: session.startTimeZoneIdentifier,
                endpoint: .start,
                earliestDate: nil,
                onSelectTimeZone: onSelectTimeZone
            )

            TimeDurationPresets(
                startTime: $session.startTime,
                endTime: $session.endTime,
                mapKitRequest: mapKitRequest,
                showsMapKitPreset: showsMapKitPreset
            )

            TimeEditorSection(
                title: "End",
                date: $session.endTime,
                timeZoneIdentifier: session.endTimeZoneIdentifier,
                endpoint: .end,
                earliestDate: session.startTime,
                onSelectTimeZone: onSelectTimeZone
            )
        }
    }
}

private struct TimeEditorSection: View {
    let title: LocalizedStringResource
    @Binding var date: Date
    let timeZoneIdentifier: String
    let endpoint: EntryTimeZoneEndpoint
    let earliestDate: Date?
    let onSelectTimeZone: (EntryTimeZoneEndpoint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                TimeEditorDateRow(date: $date, earliestDate: earliestDate)

                Divider()
                    .padding(.leading, 14)

                TimeEditorWheelPicker(
                    date: $date,
                    earliestDate: earliestDate
                )

                Divider()
                    .padding(.leading, 14)

                TimeZoneSelectionButton(
                    identifier: timeZoneIdentifier,
                    endpoint: endpoint,
                    onSelect: onSelectTimeZone
                )
            }
            .dynamicSheetSurface()
        }
        .environment(
            \.timeZone,
            TimeZone(identifier: timeZoneIdentifier) ?? .current
        )
    }
}

private struct TimeEditorDateRow: View {
    @Binding var date: Date
    let earliestDate: Date?

    var body: some View {
        HStack {
            Label("Date", systemImage: "calendar")
            Spacer()
            if let earliestDate {
                DatePicker(
                    "",
                    selection: $date,
                    in: earliestDate...,
                    displayedComponents: .date
                )
                .labelsHidden()
            } else {
                DatePicker(
                    "",
                    selection: $date,
                    displayedComponents: .date
                )
                .labelsHidden()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct TimeEditorWheelPicker: View {
    @Binding var date: Date
    let earliestDate: Date?

    var body: some View {
        Group {
            if let earliestDate {
                DatePicker(
                    "",
                    selection: $date,
                    in: earliestDate...,
                    displayedComponents: .hourAndMinute
                )
            } else {
                DatePicker(
                    "",
                    selection: $date,
                    displayedComponents: .hourAndMinute
                )
            }
        }
        .datePickerStyle(.wheel)
        .labelsHidden()
        .frame(height: 154)
        .clipped()
        .accessibilityLabel("Time")
    }
}

private struct TimeZoneSelectionButton: View {
    let identifier: String
    let endpoint: EntryTimeZoneEndpoint
    let onSelect: (EntryTimeZoneEndpoint) -> Void

    var body: some View {
        Button {
            onSelect(endpoint)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Time Zone")
                        .foregroundStyle(.primary)
                    Text(TimeZoneCatalog.title(for: identifier))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .accessibilityValue(TimeZoneCatalog.title(for: identifier))
        .accessibilityHint("Opens time zone selection")
    }
}

private struct TimeDurationPresets: View {
    @Binding var startTime: Date
    @Binding var endTime: Date
    let mapKitRequest: TimeEditorRouteRequest?
    let showsMapKitPreset: Bool

    @State private var mapKitDuration: TimeInterval?
    @State private var isLoadingMapKitDuration = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TimeDurationHeader(
                duration: max(0, endTime.timeIntervalSince(startTime))
            )

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if showsMapKitPreset {
                        MapKitDurationPreset(
                            duration: mapKitDuration,
                            isLoading: isLoadingMapKitDuration,
                            currentDuration: currentDuration,
                            onSelect: selectDuration
                        )
                    }

                    ForEach(TimeDurationPreset.fixed) { preset in
                        DurationPresetButton(
                            title: preset.title,
                            duration: preset.duration,
                            currentDuration: currentDuration,
                            onSelect: selectDuration
                        )
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 3)
            }
            .scrollIndicators(.hidden)
        }
        .task(id: mapKitRequest) {
            await loadMapKitDuration()
        }
    }

    private var currentDuration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    private func selectDuration(_ duration: TimeInterval) {
        endTime = startTime.addingTimeInterval(duration)
    }

    private func loadMapKitDuration() async {
        mapKitDuration = nil
        guard showsMapKitPreset, let mapKitRequest else {
            isLoadingMapKitDuration = false
            return
        }

        isLoadingMapKitDuration = true
        defer { isLoadingMapKitDuration = false }

        do {
            let duration = try await TransitMapKitService.estimatedTravelTime(
                from: mapKitRequest.origin.coordinate,
                to: mapKitRequest.destination.coordinate,
                routingMode: mapKitRequest.routingMode
            )
            guard !Task.isCancelled else { return }
            mapKitDuration = duration
        } catch {
            guard !Task.isCancelled else { return }
            mapKitDuration = nil
        }
    }
}

private struct TimeDurationHeader: View {
    let duration: TimeInterval

    var body: some View {
        HStack {
            Text("Duration")
                .font(.headline)
            Spacer()
            Text(TimeDurationText.compact(duration))
        }
        .padding(.horizontal, 4)
    }
}

private struct DurationPresetButton: View {
    let title: String
    let duration: TimeInterval
    let currentDuration: TimeInterval
    let onSelect: (TimeInterval) -> Void

    var body: some View {
        Button {
            onSelect(duration)
        } label: {
            DurationPill(
                title: title,
                systemImage: nil,
                isLoading: false,
                isSelected: isSelected,
                isUnavailable: false
            )
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private var isSelected: Bool {
        abs(currentDuration - duration) < 1
    }
}

private struct MapKitDurationPreset: View {
    let duration: TimeInterval?
    let isLoading: Bool
    let currentDuration: TimeInterval
    let onSelect: (TimeInterval) -> Void

    var body: some View {
        if isLoading {
            DurationPill(
                title: nil,
                systemImage: "map.fill",
                isLoading: true,
                isSelected: false,
                isUnavailable: false
            )
            .accessibilityLabel("Calculating MapKit duration")
        } else if let duration {
            Button {
                onSelect(duration)
            } label: {
                DurationPill(
                    title: TimeDurationText.compact(duration),
                    systemImage: "map.fill",
                    isLoading: false,
                    isSelected: abs(currentDuration - duration) < 1,
                    isUnavailable: false
                )
            }
            .buttonStyle(.plain)
            .accessibilityValue(
                abs(currentDuration - duration) < 1 ? "Selected" : ""
            )
        } else {
            DurationPill(
                title: "MapKit unavailable",
                systemImage: "map.fill",
                isLoading: false,
                isSelected: false,
                isUnavailable: true
            )
            .accessibilityLabel("MapKit duration unavailable")
        }
    }
}

private struct DurationPill: View {
    let title: String?
    let systemImage: String?
    let isLoading: Bool
    let isSelected: Bool
    let isUnavailable: Bool

    var body: some View {
        HStack(spacing: 7) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            if let title {
                Text(title)
            }
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(foregroundColor)
        .background(
            isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
            in: .capsule
        )
    }

    private var foregroundColor: Color {
        if isSelected {
            return .white
        }
        return isUnavailable ? .secondary : .primary
    }
}

private enum TimeDurationText {
    static func compact(_ duration: TimeInterval) -> String {
        let totalMinutes = Int((duration / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 {
            return "\(hours) hr \(minutes) min"
        }
        if hours > 0 {
            return "\(hours) hr"
        }
        return "\(minutes) min"
    }
}

#Preview("Time – Light") {
    EntryDetailTimeEditorPreview()
        .preferredColorScheme(.light)
}

#Preview("Time – Dark") {
    EntryDetailTimeEditorPreview()
        .preferredColorScheme(.dark)
}

@MainActor
private struct EntryDetailTimeEditorPreview: View {
    @State private var session = EntryDetailEditSession(
        entry: LogEntry(
            kind: .transit,
            startTime: .now,
            endTime: .now.addingTimeInterval(30 * 60),
            needsReview: false
        )
    )

    var body: some View {
        ScrollView {
            EntryDetailTimeEditor(
                session: session,
                mapKitRequest: nil,
                showsMapKitPreset: true,
                linkedCount: 0,
                onEditLinks: {},
                onSelectTimeZone: { _ in }
            )
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
