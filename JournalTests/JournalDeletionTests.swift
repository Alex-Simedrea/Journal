import SwiftData
import Testing

@testable import Journal

@Suite("Journal deletion")
@MainActor
struct JournalDeletionTests {
    @Test("Deleting an entry cascades to its details")
    func deletingEntryCascadesToDetails() throws {
        let context = try makeContext()
        let details = TransitDetails(type: "Walk")
        let entry = LogEntry(kind: .transit, needsReview: false)
        entry.transitDetails = details
        context.insert(entry)
        try context.save()

        try JournalDeletionService.delete(entry, in: context)

        #expect(try context.fetch(FetchDescriptor<LogEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TransitDetails>()).isEmpty)
    }

    @Test("Deleting a place nullifies entry references")
    func deletingPlacePreservesEntry() throws {
        let context = try makeContext()
        let place = Place(
            name: "Cafe",
            location: Location(latitude: 45.65, longitude: 25.60)
        )
        let details = PlaceVisitDetails(place: place, placeRawText: "Cafe")
        let entry = LogEntry(kind: .placeVisit, needsReview: false)
        entry.placeVisitDetails = details
        context.insert(place)
        context.insert(entry)
        try context.save()

        try JournalDeletionService.delete(place, in: context)

        let remainingEntries = try context.fetch(FetchDescriptor<LogEntry>())
        let remainingDetails = try context.fetch(
            FetchDescriptor<PlaceVisitDetails>()
        )
        #expect(remainingEntries.count == 1)
        #expect(remainingDetails.first?.place == nil)
        #expect(remainingDetails.first?.placeRawText == "Cafe")
    }

    @Test("Deleting a person removes it from existing entries")
    func deletingPersonNullifiesEntryRelationship() throws {
        let context = try makeContext()
        let person = Person(name: "Alex")
        let entry = LogEntry(kind: .transit, needsReview: false)
        entry.transitDetails = TransitDetails(type: "Walk")
        entry.people = [person]
        context.insert(person)
        context.insert(entry)
        try context.save()

        try JournalDeletionService.delete(person, in: context)

        let remainingEntry = try #require(
            context.fetch(FetchDescriptor<LogEntry>()).first
        )
        #expect(remainingEntry.people.isEmpty)
        #expect(try context.fetch(FetchDescriptor<Person>()).isEmpty)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            LogEntry.self,
            Person.self,
            Place.self,
            TransitDetails.self,
            PlaceVisitDetails.self,
            WorkoutDetails.self,
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
