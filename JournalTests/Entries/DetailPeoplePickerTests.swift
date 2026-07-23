import Foundation
import Testing

@testable import Journal

@Suite("Entry detail people picker")
@MainActor
struct EntryDetailPeoplePickerTests {
  @Test("Most used people are ordered by entry frequency")
  func mostUsedOrdering() {
    let ada = Person(name: "Ada")
    let bea = Person(name: "Bea")
    let cora = Person(name: "Cora")

    let first = LogEntry(kind: .placeVisit, needsReview: false)
    first.people = [bea, ada]
    let second = LogEntry(kind: .transit, needsReview: false)
    second.people = [bea]
    let third = LogEntry(kind: .workout, needsReview: false)
    third.people = [cora, bea]

    let usage = EntryDetailPeopleUsage.counts(in: [first, second, third])
    let projection = EntryDetailPeopleProjection(
      people: [cora, ada, bea],
      usageCounts: usage,
      searchText: ""
    )

    #expect(projection.mostUsed.map(\.name) == ["Bea", "Ada", "Cora"])
    #expect(usage[bea.id] == 3)
    #expect(usage[ada.id] == 1)
  }

  @Test("A person is counted once per entry")
  func duplicateAssociationCountsOnce() {
    let person = Person(name: "Emma")
    let entry = LogEntry(kind: .placeVisit, needsReview: false)
    entry.people = [person, person]

    let usage = EntryDetailPeopleUsage.counts(in: [entry])

    #expect(usage[person.id] == 1)
  }

  @Test("Most used grid is capped at eight people")
  func mostUsedGridLimit() {
    let people = (1...10).map { Person(name: "Person \($0)") }
    let usage = Dictionary(
      uniqueKeysWithValues: people.enumerated().map {
        ($0.element.id, people.count - $0.offset)
      }
    )

    let projection = EntryDetailPeopleProjection(
      people: people,
      usageCounts: usage,
      searchText: ""
    )

    #expect(projection.mostUsed.count == 8)
    #expect(projection.mostUsed.map(\.name) == people.prefix(8).map(\.name))
  }

  @Test("Most used grid excludes people with no usage")
  func mostUsedExcludesUnusedPeople() {
    let used = Person(name: "Used")
    let unused = Person(name: "Unused")

    let projection = EntryDetailPeopleProjection(
      people: [unused, used],
      usageCounts: [used.id: 1],
      searchText: ""
    )

    #expect(projection.mostUsed.map(\.name) == ["Used"])
  }

  @Test("Search includes aliases and preserves alphabetic sections")
  func aliasSearchAndSections() {
    let adela = Person(
      id: UUID(),
      name: "Adela",
      aliases: ["Dela"]
    )
    let stefan = Person(name: "Ștefan")
    let numeric = Person(name: "22 Jump Street")

    let search = EntryDetailPeopleProjection(
      people: [numeric, stefan, adela],
      usageCounts: [:],
      searchText: "dela"
    )
    let all = EntryDetailPeopleProjection(
      people: [numeric, stefan, adela],
      usageCounts: [:],
      searchText: ""
    )

    #expect(search.sections.map(\.id) == ["A"])
    #expect(search.sections.first?.people.map(\.name) == ["Adela"])
    #expect(all.sections.map(\.id) == ["A", "S", "#"])
  }
}
