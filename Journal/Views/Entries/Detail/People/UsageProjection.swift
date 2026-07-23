import Foundation
import SwiftUI

struct EntryDetailPeopleProjection {
  struct Section: Identifiable {
    let id: String
    let people: [Person]
  }

  let mostUsed: [Person]
  let sections: [Section]

  init(
    people: [Person],
    usageCounts: [UUID: Int],
    searchText: String
  ) {
    let alphabetized = people.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
    mostUsed = Array(
      alphabetized
        .filter { usageCounts[$0.id, default: 0] > 0 }
        .sorted { lhs, rhs in
          let lhsCount = usageCounts[lhs.id, default: 0]
          let rhsCount = usageCounts[rhs.id, default: 0]
          return lhsCount == rhsCount
            ? lhs.name.localizedStandardCompare(rhs.name)
              == .orderedAscending
            : lhsCount > rhsCount
        }
        .prefix(8)
    )

    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let filtered =
      query.isEmpty
      ? alphabetized
      : alphabetized.filter { person in
        person.name.localizedCaseInsensitiveContains(query)
          || person.aliases.contains {
            $0.localizedCaseInsensitiveContains(query)
          }
      }
    let grouped = Dictionary(grouping: filtered) { person in
      Self.sectionTitle(for: person)
    }
    sections = grouped.keys
      .sorted { lhs, rhs in
        if lhs == "#" { return false }
        if rhs == "#" { return true }
        return lhs.localizedStandardCompare(rhs) == .orderedAscending
      }
      .map { Section(id: $0, people: grouped[$0, default: []]) }
  }

  private static func sectionTitle(for person: Person) -> String {
    let trimmed = person.name.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard let firstCharacter = trimmed.first else { return "#" }
    let folded = String(firstCharacter).folding(
      options: [.diacriticInsensitive, .widthInsensitive],
      locale: .current
    )
    guard let firstFoldedCharacter = folded.first,
      firstFoldedCharacter.isLetter
    else {
      return "#"
    }
    return String(firstFoldedCharacter).uppercased()
  }
}

enum EntryDetailPeopleUsage {
  static func counts(in entries: [LogEntry]) -> [UUID: Int] {
    entries.reduce(into: [:]) { counts, entry in
      for personID in Set(entry.people.map(\.id)) {
        counts[personID, default: 0] += 1
      }
    }
  }
}
