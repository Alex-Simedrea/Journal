import SwiftData
import Testing

@testable import Journal

@Suite("Contact-backed people")
@MainActor
struct PersonContactTests {
    @Test("A contact-backed person persists only the contact identifier")
    func contactReference() {
        let person = Person(
            name: "Alex Example",
            contactIdentifier: "contact-123"
        )

        #expect(person.name == "Alex Example")
        #expect(person.contactIdentifier == "contact-123")
    }

    @Test("Manual people have no contact reference")
    func manualPerson() {
        let person = Person(name: "Manual Person")

        #expect(person.contactIdentifier == nil)
    }

    @Test("Launch sync inserts, updates, and preserves people")
    func launchSync() throws {
        let context = try makeContext()
        context.insert(Person(name: "Old Name", contactIdentifier: "contact-1"))
        context.insert(Person(name: "Manual Person"))
        try context.save()

        let firstResult = try ContactPersonSyncService.apply(
            [
                ContactSnapshot(identifier: "contact-1", name: "New Name"),
                ContactSnapshot(identifier: "contact-2", name: "Second Contact"),
            ],
            to: context
        )

        #expect(firstResult == ContactSyncResult(addedCount: 1, updatedCount: 1))

        let secondResult = try ContactPersonSyncService.apply(
            [
                ContactSnapshot(identifier: "contact-2", name: "Renamed Contact"),
            ],
            to: context
        )

        #expect(secondResult == ContactSyncResult(addedCount: 0, updatedCount: 1))

        let people = try context.fetch(FetchDescriptor<Person>())
        #expect(people.count == 3)
        #expect(people.contains { $0.name == "New Name" })
        #expect(people.contains { $0.name == "Renamed Contact" })
        #expect(people.contains { $0.name == "Manual Person" })

        let idempotentResult = try ContactPersonSyncService.apply(
            [
                ContactSnapshot(identifier: "contact-2", name: "Renamed Contact"),
            ],
            to: context
        )
        #expect(idempotentResult == ContactSyncResult(addedCount: 0, updatedCount: 0))
    }

    @Test(arguments: [
        ("Alexandru Simedrea", "AS"),
        ("Prince", "PR"),
        ("", "?"),
    ])
    func monogram(name: String, expected: String) {
        #expect(PersonMonogram.initials(for: name) == expected)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            LogEntry.self,
            Person.self,
            Place.self,
            TransitDetails.self,
            PlaceVisitDetails.self,
            TransitType.self,
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return ModelContext(container)
    }
}
