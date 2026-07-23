import MapKit
import SwiftData
import SwiftUI

struct EntryOriginalInputSection: View {
    let rawInput: String

    var body: some View {
        Section("Original input") {
            Text(rawInput)
                .textSelection(.enabled)
        }
    }
}

struct EntryModelExchangeSection: View {
    let instructions: String?
    let prompt: String?
    let toolTranscript: String?
    let response: String?

    var body: some View {
        Section("Model exchange") {
            if let instructions, let prompt, let response {
                NavigationLink("Session instructions") {
                    EntryModelPayloadView(
                        title: "Session Instructions",
                        content: instructions
                    )
                }

                NavigationLink("Full prompt") {
                    EntryModelPayloadView(
                        title: "Full Prompt",
                        content: prompt
                    )
                }

                if let toolTranscript {
                    NavigationLink("Tool calls and outputs") {
                        EntryModelPayloadView(
                            title: "Tool Calls and Outputs",
                            content: toolTranscript
                        )
                    }
                } else {
                    LabeledContent("Tool calls", value: "None")
                }

                NavigationLink("Exact response") {
                    EntryModelPayloadView(
                        title: "Exact Response",
                        content: response
                    )
                }
            } else {
                Text("The model exchange was not captured for this entry.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EntryModelPayloadView: View {
    let title: LocalizedStringResource
    let content: String

    var body: some View {
        ScrollView {
            Text(content)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
