//
//  EntryDetailEditors.swift
//  Journal
//

import PhotosUI
import SwiftUI

struct EntryDetailTimeEditor: View {
    @Bindable var session: EntryDetailEditSession

    var body: some View {
        VStack(spacing: 12) {
            EntryEditorSection(title: "Start") {
                DatePicker("Started", selection: $session.startTime)
                EntryTimeZonePicker(
                    title: "Time zone",
                    selection: $session.startTimeZoneIdentifier
                )
            }
            EntryEditorSection(title: "End") {
                DatePicker(
                    "Ended",
                    selection: $session.endTime,
                    in: session.startTime...
                )
                EntryTimeZonePicker(
                    title: "Time zone",
                    selection: $session.endTimeZoneIdentifier
                )
            }
        }
    }
}

private struct EntryTimeZonePicker: View {
    let title: LocalizedStringResource
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(EntryTimeZoneChoice.all) { choice in
                Text(choice.title).tag(choice.identifier)
            }
        }
    }
}

private struct EntryTimeZoneChoice: Identifiable {
    let identifier: String
    let title: String
    var id: String { identifier }

    static let all: [EntryTimeZoneChoice] = TimeZone
        .knownTimeZoneIdentifiers
        .map {
            EntryTimeZoneChoice(
                identifier: $0,
                title: $0.replacingOccurrences(of: "_", with: " ")
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
}
