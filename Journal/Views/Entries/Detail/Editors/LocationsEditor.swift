import PhotosUI
import SwiftUI

struct EntryDetailLocationsEditor: View {
    let entry: LogEntry
    let session: EntryDetailEditSession
    let onSelect: (EntryDetailLocationRole) -> Void

    var body: some View {
        VStack(spacing: 10) {
            if entry.kind == .placeVisit
                || entry.workoutDetails?.movementKind != .moving {
                EntryLocationHubButton(
                    role: .place,
                    selection: session.selection(for: .place),
                    onSelect: onSelect
                )
            } else {
                EntryLocationHubButton(
                    role: .origin,
                    selection: session.selection(for: .origin),
                    onSelect: onSelect
                )
                EntryLocationHubButton(
                    role: .destination,
                    selection: session.selection(for: .destination),
                    onSelect: onSelect
                )
            }
        }
    }
}

private struct EntryLocationHubButton: View {
    let role: EntryDetailLocationRole
    let selection: EntryLocationSelection?
    let onSelect: (EntryDetailLocationRole) -> Void

    var body: some View {
        Button { onSelect(role) } label: {
            HStack(spacing: 12) {
                if let selection {
                    TimelineFixedPlaceSymbol(
                        systemImage: selection.systemImage,
                        size: 28
                    )
                } else {
                    TimelineFixedSymbol(
                        systemName: "mappin.slash",
                        size: 28
                    )
                    .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(role.title).font(.headline)
                    Text(selection?.title ?? String(localized: "Needs review"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                EntryDetailChevron()
            }
            .padding()
            .background(.background, in: .rect(cornerRadius: 18))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
