import MapKit
import Photos
import SwiftUI

struct TimelinePeopleTile: View {
    let people: [TimelinePersonSnapshot]
    let needsReview: Bool

    var body: some View {
        HStack(spacing: 7) {
            if people.isEmpty {
                TimelineFixedSymbol(
                    systemName: "person.crop.circle.badge.questionmark",
                    size: 22
                )
                Text("People need review")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
            } else if people.count <= 2 {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(people) { person in
                        TimelineNamedPerson(person: person)
                    }
                }
            } else if let first = people.first {
                TimelinePeopleGroup(
                    first: first,
                    remaining: Array(people.dropFirst())
                )
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .tertiarySystemGroupedBackground),
            in: .rect(cornerRadius: 16)
        )
        .overlay(alignment: .topTrailing) {
            if needsReview {
                TimelineReviewBadge().padding(5)
            }
        }
    }
}

struct TimelinePeopleGroup: View {
    let first: TimelinePersonSnapshot
    let remaining: [TimelinePersonSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TimelineNamedPerson(person: first)
            TimelinePeopleSummary(people: remaining)
        }
    }
}

struct TimelineNamedPerson: View {
    let person: TimelinePersonSnapshot

    var body: some View {
        HStack(spacing: 4) {
            PersonAvatar(
                name: person.name,
                contactIdentifier: person.contactIdentifier,
                size: 20
            )
            Text(person.name)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TimelinePeopleSummary: View {
    let people: [TimelinePersonSnapshot]

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: -8) {
                ForEach(people.prefix(3)) { person in
                    PersonAvatar(
                        name: person.name,
                        contactIdentifier: person.contactIdentifier,
                        size: 20
                    )
                }
            }
            Text("\(people.count) more")
                .font(.footnote.weight(.medium))
                .lineLimit(1)
        }
    }
}
