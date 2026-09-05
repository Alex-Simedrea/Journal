import SwiftUI

struct EntryLinkDisclosureRow: View {
    let linkedCount: Int
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: linkedCount == 0 ? "link.badge.plus" : "link")
                    .frame(width: 22)
                    .foregroundStyle(
                        linkedCount == 0
                            ? AnyShapeStyle(.secondary)
                            : AnyShapeStyle(.tint)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Linked Entries")
                        .foregroundStyle(.primary)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                DisclosureChevron()
            }
            .contentShape(.rect)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .dynamicSheetSurface()
    }

    private var status: String {
        switch linkedCount {
        case 0: String(localized: "Not linked")
        case 1: String(localized: "Linked to one entry")
        default: String(localized: "Linked above and below")
        }
    }
}

struct EntryLinkEditor: View {
    let entry: LogEntry
    let entries: [LogEntry]
    let onSelect: (LogEntry) -> Void

    var body: some View {
        Group {
            if previous == nil && next == nil {
                ContentUnavailableView(
                    "No Entries to Link",
                    systemImage: "link",
                    description: Text(
                        "Add a time and location to a nearby entry first."
                    )
                )
                .padding(.vertical, 8)
            } else {
                TimelineRulerSequence(
                    rows: timelineRows,
                    pendingAutomationCandidateIDsByEntryID: [:],
                    onSelect: selectTimelineEntry,
                    onAcceptCandidateEntry: { _, _ in },
                    onDismissCandidate: { _ in },
                    onAddTransit: { _ in },
                    expandsMovementCards: true,
                    dimmedEntryIDs: [entry.id],
                    showsTransitGapActions: false,
                    linkHighlightedEntryIDs: linkHighlightedEntryIDs,
                    linkedEndBoundaryEntryIDs: linkedEndBoundaryEntryIDs,
                    endCapHeight: edgeInset,
                    fixedSeparatedEntryGap: 16
                )
                .mask(fadeMask)
            }
        }
    }

    private var ordered: [LogEntry] {
        EntryLinkingService.ordered(
            entries.filter { $0.id != entry.id } + [entry]
        )
    }

    private var currentIndex: Int? {
        ordered.firstIndex { $0.id == entry.id }
    }

    private var previous: LogEntry? {
        guard let index = currentIndex, index > ordered.startIndex else {
            return nil
        }
        let value = ordered[index - 1]
        return EntryLinkingService.canLink(entry, to: value) ? value : nil
    }

    private var next: LogEntry? {
        guard let index = currentIndex, index + 1 < ordered.endIndex else {
            return nil
        }
        let value = ordered[index + 1]
        return EntryLinkingService.canLink(entry, to: value) ? value : nil
    }

    private var displayedEntries: [LogEntry] {
        [previous, entry, next].compactMap { $0 }
    }

    private var linkHighlightedEntryIDs: Set<UUID> {
        Set(
            [previous, next].compactMap { $0 }.filter {
                EntryLinkingService.isLinked(entry, to: $0)
            }.map(\.id)
        )
    }

    private var linkedEndBoundaryEntryIDs: Set<UUID> {
        var result: Set<UUID> = []
        if let previous,
            EntryLinkingService.isLinked(entry, to: previous) {
            result.insert(previous.id)
        }
        if let next,
            EntryLinkingService.isLinked(entry, to: next) {
            result.insert(entry.id)
        }
        return result
    }

    private var timelineRows: [TimelineRow] {
        let date = entry.startTime ?? entry.endTime ?? entry.createdAt
        let zone =
            TimeZone(identifier: entry.startTimeZoneIdentifier) ?? .current
        let day = TimelineDayKey(date: date, timeZone: zone)
        return TimelineProjection.project(
            entries: displayedEntries.map(TimelineEntrySnapshot.init(entry:)),
            for: day
        ).rows
    }

    private let edgeInset: CGFloat = 16

    private var fadeMask: some View {
        GeometryReader { proxy in
            let edge = min(edgeInset / max(proxy.size.height, 1), 0.2)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.18), location: edge * 0.38),
                    .init(color: .white.opacity(0.58), location: edge * 0.72),
                    .init(color: .white, location: edge),
                    .init(color: .white, location: 1 - edge),
                    .init(
                        color: .white.opacity(0.58),
                        location: 1 - edge * 0.72
                    ),
                    .init(
                        color: .white.opacity(0.18),
                        location: 1 - edge * 0.38
                    ),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func selectTimelineEntry(_ id: UUID) {
        guard id != entry.id,
            let candidate = [previous, next].compactMap({ $0 }).first(where: {
                $0.id == id
            })
        else { return }
        onSelect(candidate)
    }
}

struct EntryLinkResolutionEditor: View {
    let entry: LogEntry
    let neighbor: LogEntry
    @Binding var timeSource: EntryLinkValueSource
    @Binding var placeSource: EntryLinkValueSource
    var includesTime = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if includesTime && !timesMatch {
                choiceSection(
                    title: "Time",
                    selection: $timeSource,
                    isEnabled: isTimeSourceSelectable
                ) {
                    choice in
                    TimeChoiceCard(
                        value: value(for: choice),
                        summary: summary(for: choice)
                    )
                }
            }
            if !placesMatch {
                choiceSection(
                    title: "Place",
                    selection: $placeSource,
                    isEnabled: isPlaceSourceSelectable
                ) {
                    choice in
                    PlaceChoiceCard(
                        value: value(for: choice),
                        summary: summary(for: choice)
                    )
                }
            }
        }
    }

    private var values:
        (current: EntryBoundaryValue, neighbor: EntryBoundaryValue)?
    {
        let sides = EntryLinkingService.boundarySides(for: entry, and: neighbor)
        guard
            let current = EntryLinkingService.boundary(
                of: entry,
                side: sides.entry
            ),
            let neighborValue = EntryLinkingService.boundary(
                of: neighbor,
                side: sides.neighbor
            )
        else { return nil }
        return (current, neighborValue)
    }

    private var timesMatch: Bool {
        values.map {
            EntryLinkingService.boundaryTimesMatch(
                $0.current.time, $0.neighbor.time
            )
        } ?? true
    }

    private var placesMatch: Bool {
        EntryLinkingService.boundaryPlacesMatch(entry, neighbor)
    }

    private func value(for source: EntryLinkValueSource) -> EntryBoundaryValue {
        let values = values!
        return source == .current ? values.current : values.neighbor
    }

    private func summary(for source: EntryLinkValueSource) -> String {
        EntryLinkingService.summary(for: source == .current ? entry : neighbor)
    }

    private func isTimeSourceSelectable(_ source: EntryLinkValueSource) -> Bool
    {
        guard entry.kind == .workout || neighbor.kind == .workout else {
            return true
        }
        return (source == .current ? entry : neighbor).kind == .workout
    }

    private func isPlaceSourceSelectable(_ source: EntryLinkValueSource) -> Bool
    {
        guard entry.kind == .workout || neighbor.kind == .workout else {
            return true
        }
        return value(for: source).placeID != nil
    }

    private func choiceSection<Card: View>(
        title: LocalizedStringResource,
        selection: Binding<EntryLinkValueSource>,
        isEnabled: @escaping (EntryLinkValueSource) -> Bool = { _ in true },
        @ViewBuilder card: @escaping (EntryLinkValueSource) -> Card
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).padding(.horizontal, 4)
            HStack(spacing: 10) {
                ForEach(EntryLinkValueSource.allCases) { source in
                    Button {
                        selection.wrappedValue = source
                    } label: {
                        card(source)
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        selection.wrappedValue == source
                                            ? Color.blue : Color.clear,
                                        lineWidth: 2
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled(source))
                    .opacity(isEnabled(source) ? 1 : 0.45)
                }
            }
        }
    }
}

private struct TimeChoiceCard: View {
    let value: EntryBoundaryValue
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.time.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(
            maxWidth: .infinity,
            minHeight: 72,
            maxHeight: 72,
            alignment: .leading
        )
        .background(.background, in: .rect(cornerRadius: 16))
    }
}

private struct PlaceChoiceCard: View {
    let value: EntryBoundaryValue
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                FixedSizePlaceSymbol(systemImage: value.systemImage, size: 17)
                Text(value.name).lineLimit(1)
            }
            .font(.headline)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(
            maxWidth: .infinity,
            minHeight: 72,
            maxHeight: 72,
            alignment: .leading
        )
        .background(.background, in: .rect(cornerRadius: 16))
    }
}
