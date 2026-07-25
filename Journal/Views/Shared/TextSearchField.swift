import SwiftUI

struct SearchField: View {
    let prompt: LocalizedStringResource
    @Binding var text: String
    var capitalization: TextInputAutocapitalization? = nil
    var disablesAutocorrection = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(prompt, text: $text)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(disablesAutocorrection)

            if !text.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") {
                    text = ""
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }
}
