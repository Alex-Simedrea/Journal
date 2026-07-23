//
//  EntryDetailPeopleEditor.swift
//  Journal
//

import Foundation
import SwiftUI

struct EntryDetailPeopleEditor: View {
  @Bindable var session: EntryDetailEditSession
  let topContentInset: CGFloat
  @Binding var isScrolled: Bool
  @Binding var searchText: String
  let people: [Person]
  let usageCounts: [UUID: Int]

  private var projection: EntryDetailPeopleProjection {
    EntryDetailPeopleProjection(
      people: people,
      usageCounts: usageCounts,
      searchText: searchText
    )
  }

  var body: some View {
    DynamicSheetScrollView(
      fillsAvailableHeight: true,
      indexItems: scrollIndexItems,
      topContentInset: topContentInset,
      isScrolled: $isScrolled
    ) {
      EntryDetailPeopleContent(
        projection: projection,
        hasPeople: !people.isEmpty,
        searchText: searchText,
        selectedPeopleIDs: session.selectedPeopleIDs,
        onSelect: toggleSelection
      )
      .padding(.horizontal, 16)
      .padding(.bottom, 18)
    }
  }

  private var scrollIndexItems: [DynamicSheetScrollIndexItem] {
    var items: [DynamicSheetScrollIndexItem] = []
    if !projection.mostUsed.isEmpty {
      items.append(
        DynamicSheetScrollIndexItem(
          id: EntryDetailPeopleScrollTarget.mostUsed,
          systemImage: "star.fill"
        )
      )
    }
    items += projection.sections.map {
      DynamicSheetScrollIndexItem(id: $0.id, title: $0.id)
    }
    return items
  }

  private func toggleSelection(_ person: Person) {
    if session.selectedPeopleIDs.contains(person.id) {
      session.selectedPeopleIDs.remove(person.id)
    } else {
      session.selectedPeopleIDs.insert(person.id)
    }
  }
}

enum EntryDetailPeopleScrollTarget {
  static let mostUsed = "people-most-used"
}

struct EntryDetailPeopleContent: View {
  let projection: EntryDetailPeopleProjection
  let hasPeople: Bool
  let searchText: String
  let selectedPeopleIDs: Set<UUID>
  let onSelect: (Person) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if !projection.mostUsed.isEmpty {
        EntryDetailMostUsedPeopleGrid(
          people: projection.mostUsed,
          selectedPeopleIDs: selectedPeopleIDs,
          onSelect: onSelect
        )
        .id(EntryDetailPeopleScrollTarget.mostUsed)
      }

      if !hasPeople {
        ContentUnavailableView(
          "No People",
          systemImage: "person.2.slash",
          description: Text("Add someone to select them here.")
        )
        .frame(maxWidth: .infinity)
      } else if projection.sections.isEmpty {
        ContentUnavailableView.search(text: searchText)
          .frame(maxWidth: .infinity)
      } else {
        VStack(spacing: 12) {
          ForEach(projection.sections) { section in
            EntryDetailPeopleListSection(
              section: section,
              selectedPeopleIDs: selectedPeopleIDs,
              onSelect: onSelect
            )
            .id(section.id)
          }
        }
        .padding(.trailing, 22)
        .padding(.trailing, -16)
      }
    }
  }
}

struct EntryDetailMostUsedPeopleGrid: View {
  let people: [Person]
  let selectedPeopleIDs: Set<UUID>
  let onSelect: (Person) -> Void

  private let columns = Array(
    repeating: GridItem(.flexible(), spacing: 8),
    count: 4
  )

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Most Used", systemImage: "star.fill")
        .font(.headline)

      LazyVGrid(columns: columns, spacing: 12) {
        ForEach(people) { person in
          EntryDetailFrequentPersonButton(
            person: person,
            selected: selectedPeopleIDs.contains(person.id),
            onSelect: { onSelect(person) }
          )
        }
      }
    }
  }
}
