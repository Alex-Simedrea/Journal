//
//  EntryPeopleSelectionSection.swift
//  Journal
//

import SwiftUI

struct EntryPeopleSelectionSection: View {
    let people: [Person]
    let selectedIDs: Set<UUID>
    let onToggle: (UUID) -> Void

    var body: some View {
        if !people.isEmpty {
            Section("People") {
                ForEach(people) { person in
                    EntryPersonSelectionRow(
                        name: person.name,
                        contactIdentifier: person.contactIdentifier,
                        isSelected: selectedIDs.contains(person.id),
                        onSelect: { onToggle(person.id) }
                    )
                }
            }
        }
    }
}

private struct EntryPersonSelectionRow: View {
    let name: String
    let contactIdentifier: String?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                PersonAvatar(
                    name: name,
                    contactIdentifier: contactIdentifier,
                    size: 34
                )
                Text(name)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
    }
}
