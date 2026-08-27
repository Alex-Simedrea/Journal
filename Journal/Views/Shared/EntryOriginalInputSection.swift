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
