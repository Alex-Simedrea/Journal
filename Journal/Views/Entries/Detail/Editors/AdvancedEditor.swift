import PhotosUI
import SwiftUI

struct EntryDetailAdvancedEditor: View {
    let entry: LogEntry

    var body: some View {
        VStack(spacing: 12) {
            EntryAdvancedValueCard(title: "Original Input", value: entry.rawInputString)
            EntryAdvancedValueCard(title: "Instructions", value: entry.modelInstructions)
            EntryAdvancedValueCard(title: "Prompt", value: entry.modelPrompt)
            EntryAdvancedValueCard(title: "Tool Transcript", value: entry.modelToolTranscript)
            EntryAdvancedValueCard(title: "Response", value: entry.modelResponse)
        }
    }
}

private struct EntryAdvancedValueCard: View {
    let title: LocalizedStringResource
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(value ?? String(localized: "Unavailable"))
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(value == nil ? .secondary : .primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 16))
    }
}
