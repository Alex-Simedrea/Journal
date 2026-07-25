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
