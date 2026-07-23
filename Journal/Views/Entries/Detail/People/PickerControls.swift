import Foundation
import SwiftUI

struct EntryDetailFrequentPersonButton: View {
  let person: Person
  let selected: Bool
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      VStack(spacing: 6) {
        EntryDetailSelectableAvatar(
          person: person,
          size: 56,
          selected: selected
        )

        Text(person.name)
          .font(.caption)
          .foregroundStyle(.primary)
          .lineLimit(1)
          .frame(width: 72)
      }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

struct EntryDetailPeopleSearchField: View {
  @Binding var text: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)

      TextField("Search People", text: $text)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()

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

struct EntryDetailPeopleListSection: View {
  let section: EntryDetailPeopleProjection.Section
  let selectedPeopleIDs: Set<UUID>
  let onSelect: (Person) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(section.id)
        .font(.headline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)

      VStack(spacing: 0) {
        ForEach(Array(section.people.enumerated()), id: \.element.id) {
          index,
          person in
          Button {
            onSelect(person)
          } label: {
            HStack(spacing: 12) {
              EntryDetailSelectableAvatar(
                person: person,
                size: 42,
                selected: selectedPeopleIDs.contains(person.id)
              )
              Text(person.name)
                .foregroundStyle(.primary)
              Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 56)
            .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(
            selectedPeopleIDs.contains(person.id) ? .isSelected : []
          )

          if index < section.people.count - 1 {
            Divider()
              .padding(.leading, 66)
              .padding(.trailing, 16)
          }
        }
      }
      .background(.tertiary.opacity(0.7), in: .rect(cornerRadius: 24))
    }
  }
}

struct EntryDetailSelectableAvatar: View {
  let person: Person
  let size: CGFloat
  let selected: Bool

  var body: some View {
    PersonAvatar(
      name: person.name,
      contactIdentifier: person.contactIdentifier,
      size: size
    )
    .blur(radius: selected ? 1 : 0)
    .clipShape(.circle)
    .overlay {
      if selected {
        ZStack {
          Color.accentColor
            .opacity(0.4)
          Image(systemName: "checkmark")
            .foregroundStyle(.white)
        }
        .clipShape(.circle)
      }
    }
  }
}

#if DEBUG
  @MainActor
  private struct EntryDetailPeopleEditorPreview: View {
    private let people: [Person]
    private let usageCounts: [UUID: Int]
    @State private var session: EntryDetailEditSession
    @State private var isScrolled = false
    @State private var searchText = ""

    init() {
      let names = [
        "Adela Florea", "Adi Rădulescu", "Andi Coleg", "Bianca Pop",
        "Cristi Munteanu", "David Ionescu", "Emma Dumitru",
        "Matei Cazacu",
        "Nora Pavel", "Ștefan Luca", "Teodor Stan", "Zoe Marinescu",
      ]
      let people = names.map { Person(name: $0) }
      let entry = LogEntry(kind: .placeVisit, needsReview: false)
      entry.people = [people[0], people[2], people[6]]
      self.people = people
      usageCounts = Dictionary(
        uniqueKeysWithValues: people.enumerated().map {
          ($0.element.id, max(1, people.count - $0.offset))
        }
      )
      _session = State(initialValue: EntryDetailEditSession(entry: entry))
    }

    var body: some View {
      EntryDetailPeopleEditor(
        session: session,
        topContentInset: 80,
        isScrolled: $isScrolled,
        searchText: $searchText,
        people: people,
        usageCounts: usageCounts
      )
      .background(.regularMaterial)
    }
  }

  #Preview("People editor") {
    EntryDetailPeopleEditorPreview()
  }
#endif
