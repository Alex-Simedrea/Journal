//
//  EntryDetailPeopleCard.swift
//  Journal
//

import SwiftUI

struct EntryDetailPeopleCard: View {
    let people: [Person]
    let needsReview: Bool
    let onEdit: () -> Void

    var body: some View {
        let presentation = EntryDetailPeoplePresentation(people: people)
        Button(action: onEdit) {
            VStack(spacing: 1) {
                if people.isEmpty {
                    EntryDetailEmptyPeopleContent()
                } else {
                    EntryDetailPeopleConstellation(
                        people: presentation.visiblePeople
                    )
                    EntryDetailPeopleLabel(presentation: presentation)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 94, alignment: .center)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(maxHeight: .infinity)
        .background(.background, in: .rect(cornerRadius: 22))
        .overlay(alignment: .topTrailing) {
            EntryDetailChevron()
                .padding(.top, 9)
                .padding(.trailing, 12)
        }
        .overlay(alignment: .bottomTrailing) {
            if needsReview {
                EntryDetailReviewBadge().padding(8)
            }
        }
    }
}

struct EntryDetailPeoplePresentation {
    let visiblePeople: [Person]
    let namedPeople: [Person]
    let remainingNameCount: Int

    init(people: [Person]) {
        visiblePeople = Array(people.prefix(12))
        let namedCount = people.count > 4 ? 3 : people.count
        namedPeople = Array(people.prefix(namedCount))
        remainingNameCount = max(0, people.count - namedCount)
    }
}

private struct EntryDetailEmptyPeopleContent: View {
    var body: some View {
        VStack(spacing: 2) {
            TimelineFixedSymbol(
                systemName: "person.3.fill",
                size: 38,
                weight: .semibold
            )
            Text("No other people")
                .font(.subheadline)
        }
        .foregroundStyle(.secondary)
    }
}

private struct EntryDetailPeopleConstellation: View {
    let people: [Person]

    var body: some View {
        let placements = EntryDetailPeopleConstellationMetrics.placements(
            count: people.count
        )
        GeometryReader { proxy in
            let scale = EntryDetailPeopleConstellationMetrics.scale(
                for: proxy.size.width,
                placements: placements
            )
            ZStack {
                ForEach(people.enumerated(), id: \.element.id) { index, person in
                    let placement = placements[index]
                    EntryDetailConstellationAvatar(
                        person: person,
                        size: placement.diameter * scale
                    )
                    .position(
                        x: proxy.size.width / 2
                            + placement.center.x * scale,
                        y: proxy.size.height / 2
                            + placement.center.y * scale
                    )
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: EntryDetailPeopleConstellationMetrics.height,
            maxHeight: EntryDetailPeopleConstellationMetrics.height
        )
    }
}

private struct EntryDetailConstellationAvatar: View {
    let person: Person
    let size: CGFloat

    var body: some View {
        PersonAvatar(
            name: person.name,
            contactIdentifier: person.contactIdentifier,
            size: size
        )
    }
}

private struct EntryDetailPeopleLabel: View {
    @Environment(\.locale) private var locale

    let presentation: EntryDetailPeoplePresentation

    var body: some View {
        if presentation.remainingNameCount == 0 {
            Text(
                presentation.namedPeople.map(\.name).formatted(
                    .list(type: .and, width: .short).locale(locale)
                )
            )
            .font(.caption2.bold())
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        } else {
            Text(
                "\(namePrefix) & \(presentation.remainingNameCount) more",
                comment: "People card summary. The first value is a comma-separated list of names and the second is the number of additional people."
            )
            .font(.caption2.bold())
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    private var namePrefix: String {
        presentation.namedPeople.map(\.name).joined(separator: ", ")
    }
}
