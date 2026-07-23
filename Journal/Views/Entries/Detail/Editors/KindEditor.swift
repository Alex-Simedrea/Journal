import PhotosUI
import SwiftUI

struct EntryDetailKindEditor: View {
    @Bindable var session: EntryDetailEditSession
    let entry: LogEntry
    let transitTypes: [TransitType]

    var body: some View {
        VStack(spacing: 12) {
            if let reason = entry.entryKindReviewReason {
                Label(reason, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            EntryEditorSection(title: "Entry Type") {
                Picker("Type", selection: $session.targetKind) {
                    Text("Transit").tag(LogKind.transit)
                    Text("Place").tag(LogKind.placeVisit)
                }
                .pickerStyle(.segmented)
                if session.targetKind == .transit {
                    Picker("Transit type", selection: $session.transitType) {
                        ForEach(transitTypes) { type in
                            Text(type.canonicalName).tag(type.canonicalName)
                        }
                    }
                }
            }
            Text("Any fields that cannot be carried across will remain marked for review.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
