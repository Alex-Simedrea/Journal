import SwiftUI

struct TimelinePeopleTile: View {
    let people: [TimelinePersonSnapshot]
    let needsReview: Bool

    var body: some View {
        GeometryReader { proxy in
            if people.isEmpty {
                FixedSizeSymbol(
                    systemName: "person.crop.circle.badge.questionmark",
                    size: 24
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let visiblePeople = Array(people.prefix(12))
                let verticalPadding = 2.0
                let contentHeight = max(
                    0,
                    proxy.size.height - verticalPadding * 2
                )
                let placements = EntryDetailPeopleConstellationMetrics.placements(
                    count: visiblePeople.count
                )
                let widthScale = EntryDetailPeopleConstellationMetrics.scale(
                    for: proxy.size.width,
                    placements: placements
                )
                let heightScale = contentHeight
                    / EntryDetailPeopleConstellationMetrics.height
                let scale = min(widthScale, heightScale)

                ZStack {
                    ForEach(
                        visiblePeople.enumerated(),
                        id: \.element.id
                    ) { index, person in
                        let placement = placements[index]
                        PersonAvatar(
                            name: person.name,
                            contactIdentifier: person.contactIdentifier,
                            size: placement.diameter * scale
                        )
                        .position(
                            x: proxy.size.width / 2
                                + placement.center.x * scale,
                            y: verticalPadding + contentHeight / 2
                                + placement.center.y * scale
                        )
                    }
                }
            }
        }
        .background(
            Color(uiColor: .tertiarySystemGroupedBackground),
            in: .rect(cornerRadius: 16)
        )
        .overlay(alignment: .topTrailing) {
            if needsReview {
                ReviewBadge(size: 17).padding(5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard !people.isEmpty else {
            return String(localized: "People need review")
        }
        return people.map(\.name).formatted(.list(type: .and, width: .short))
    }
}

struct TimelinePeopleAvatarStack: View {
    let people: [TimelinePersonSnapshot]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(people.prefix(3)) { person in
                PersonAvatar(
                    name: person.name,
                    contactIdentifier: person.contactIdentifier,
                    size: 20
                )
            }
        }
    }
}
