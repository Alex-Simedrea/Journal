import SwiftUI

struct TimelineUnplacedSection: View {
    let occurrences: [TimelineOccurrence]
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "Unplaced Entries",
                systemImage: "clock.badge.exclamationmark"
            )
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(occurrences) { occurrence in
                TimelineEntryCard(
                    occurrence: occurrence,
                    onTap: { onSelect(occurrence.entryID) }
                )
            }
        }
        .padding(.horizontal)
        .padding(.top, 28)
    }
}

struct TimelineReviewBadge: View {
    var body: some View {
        Image(systemName: "exclamationmark")
            .resizable()
            .scaledToFit()
            .fontWeight(.black)
            .foregroundStyle(.white)
            .frame(width: 3, height: 9)
            .frame(width: 17, height: 17)
            .background(.orange, in: .circle)
            .accessibilityLabel("Needs review")
    }
}
