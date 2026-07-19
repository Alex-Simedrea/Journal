//
//  LibraryScreen.swift
//  Journal
//
//  Created by Alexandru Simedrea on 12/07/2026.
//

import SwiftData
import SwiftUI

struct LibraryScreen: View {
    var body: some View {
        List {
            NavigationLink(
                "Places",
                destination: PlacesList()
                    .navigationTitle("Places")
                    .navigationBarTitleDisplayMode(.large)
            )

            NavigationLink(
                "People",
                destination: PeopleList()
                    .navigationTitle("People")
                    .navigationBarTitleDisplayMode(.large)
            )
        }
        .navigationTitle("Library")
        .toolbarTitleDisplayMode(.inlineLarge)
    }
}

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

struct PlacesList: View {
    @Query private var places: [Place]
    @State private var selectedPlace: Place?

    var body: some View {
        List(places) { place in
            Button {
                selectedPlace = place
            } label: {
                PlaceRow(
                    name: place.name,
                    address: place.location.formattedAddress,
                    systemImage: place.systemImage
                )
            }
            .buttonStyle(.plain)
        }
        .sheet(item: $selectedPlace) { place in
            PlaceDetailSheet(place: place)
        }
    }
}

private struct PlaceRow: View {
    let name: String
    let address: String?
    let systemImage: PlaceSystemImage

    var body: some View {
        HStack(spacing: 12) {
            PlaceSymbolImage(systemImage: systemImage)
                .font(.system(size: 24))

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)

                if let address {
                    Text(address)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .contentShape(.rect)
    }
}
