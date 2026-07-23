import MapKit
import Photos
import SwiftUI

struct EntryDetailChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct EntryDetailReviewBadge: View {
    var body: some View {
        Image(systemName: "exclamationmark")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(.orange, in: .circle)
            .accessibilityLabel("Needs review")
    }
}


struct EntryDetailSectionButton: View {
    let title: LocalizedStringResource
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(title).font(.title3.bold())
                Spacer()
                EntryDetailChevron()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
    }
}
