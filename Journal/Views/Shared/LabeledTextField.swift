import SwiftUI

struct LabeledTextField: View {
    let title: LocalizedStringResource
    let prompt: LocalizedStringResource
    @Binding var text: String
    var capitalization: TextInputAutocapitalization? = nil
    var disablesAutocorrection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField(prompt, text: $text)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(disablesAutocorrection)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    .background.opacity(0.7),
                    in: .rect(cornerRadius: 24)
                )
        }
    }
}
