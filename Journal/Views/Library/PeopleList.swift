import SwiftData
import SwiftUI

struct PeopleList: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.name) private var people: [Person]
    @State private var syncErrorMessage: String?
    @State private var selectedPerson: Person?

    var body: some View {
        PeopleListContent(
            people: people,
            onSelect: { selectedPerson = $0 }
        )
            .task {
                do {
                    _ = try await ContactPersonSyncService
                        .synchronizeAllContacts(in: modelContext)
                } catch {
                    syncErrorMessage = error.localizedDescription
                }
            }
            .alert(
                "Couldn’t Refresh Contacts",
                isPresented: Binding(
                    get: { syncErrorMessage != nil },
                    set: { if !$0 { syncErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(syncErrorMessage ?? "An unknown error occurred.")
            }
            .sheet(item: $selectedPerson) { person in
                PersonDetailSheet(person: person)
            }
    }
}

private struct PeopleListContent: View {
    let people: [Person]
    let onSelect: (Person) -> Void

    var body: some View {
        if people.isEmpty {
            ContentUnavailableView {
                Label("No People Yet", systemImage: "person.2")
            } description: {
                Text("Contacts are imported automatically, or you can add someone manually.")
            }
        } else {
            List(people) { person in
                Button {
                    onSelect(person)
                } label: {
                    PersonRow(
                        name: person.name,
                        contactIdentifier: person.contactIdentifier
                    )
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }
}

private struct PersonRow: View {
    let name: String
    let contactIdentifier: String?

    var body: some View {
        HStack(spacing: 12) {
            PersonAvatar(
                name: name,
                contactIdentifier: contactIdentifier,
                size: 48
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)

                if contactIdentifier == nil {
                    Text("Manual")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Contacts")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
