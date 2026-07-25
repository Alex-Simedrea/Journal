import SwiftUI

struct DisclosureChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct DisclosureSectionButton: View {
    let title: LocalizedStringResource
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(title).font(.title3.bold())
                Spacer()
                DisclosureChevron()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
    }
}
