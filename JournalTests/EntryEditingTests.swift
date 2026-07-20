import Foundation
import SwiftData
import Testing

@testable import Journal

@Suite("Entry attachments and transit editing")
@MainActor
struct EntryEditingTests {
    @Test("Photo attachments persist as asset references")
    func photoReferencesPersist() throws {
        let context = try makeContext()
        let entry = LogEntry(
            kind: .transit,
            photoReferences: [
                PhotoReference(
                    assetLocalIdentifier: "photo-library-identifier",
                    addedAt: Date(timeIntervalSince1970: 100)
                ),
            ],
            needsReview: false
        )
        entry.transitDetails = TransitDetails(type: "Walk")
        context.insert(entry)
        try context.save()

        let storedEntry = try #require(
            context.fetch(FetchDescriptor<LogEntry>()).first
        )
        let reference = try #require(storedEntry.photoReferences.first)

        #expect(storedEntry.photoReferences.count == 1)
        #expect(reference.assetLocalIdentifier == "photo-library-identifier")
        #expect(reference.addedAt == Date(timeIntervalSince1970: 100))
    }

    @Test("Transit editing updates shared entry fields and details")
    func editTransit() throws {
        let context = try makeContext()
        let origin = Place(
            name: "Home",
            location: Location(
                latitude: 45.65,
                longitude: 25.60,
                timeZoneIdentifier: "Europe/Bucharest"
            )
        )
        let oldDestination = Place(
            name: "Old Destination",
            location: Location(latitude: 45.66, longitude: 25.61)
        )
        let newDestination = Place(
            name: "New Destination",
            location: Location(
                latitude: 40.71,
                longitude: -74.00,
                timeZoneIdentifier: "America/New_York"
            )
        )
        let person = Person(name: "Alex")
        let originalStart = Date(timeIntervalSince1970: 1_000)
        let originalEnd = Date(timeIntervalSince1970: 2_000)
        let entry = LogEntry(
            kind: .transit,
            startTime: originalStart,
            endTime: originalEnd,
            needsReview: true
        )
        entry.transitDetails = TransitDetails(
            type: "Car",
            originPlace: origin,
            destinationPlace: oldDestination,
            durationSource: .mapkitCarFallback,
            fieldReviews: [
                TransitFieldReview(field: .destination, reason: "Ambiguous"),
            ]
        )

        context.insert(origin)
        context.insert(oldDestination)
        context.insert(newDestination)
        context.insert(person)
        context.insert(entry)
        try context.save()

        let model = TransitEditModel(entry: entry)
        model.transitType = "Walk"
        model.destinationPlaceID = newDestination.id
        model.startTime = Date(timeIntervalSince1970: 3_000)
        model.endTime = Date(timeIntervalSince1970: 4_000)
        model.selectedPeopleIDs = [person.id]

        let didSave = model.save(
            entry: entry,
            places: [origin, oldDestination, newDestination],
            people: [person],
            in: context
        )

        #expect(didSave)
        #expect(entry.transitDetails?.type == "Walk")
        #expect(entry.transitDetails?.destinationPlace?.id == newDestination.id)
        #expect(entry.startTime == Date(timeIntervalSince1970: 3_000))
        #expect(entry.endTime == Date(timeIntervalSince1970: 4_000))
        #expect(entry.endTimeZoneIdentifier == "America/New_York")
        #expect(entry.timeConfidence == .manualOverride)
        #expect(entry.transitDetails?.durationSource == .manualOverride)
        #expect(entry.people.map(\.id) == [person.id])
        #expect(entry.needsReview == false)
        #expect(entry.transitDetails?.fieldReviews.isEmpty == true)
    }

    @Test("Workout editing updates people without changing HealthKit data")
    func editWorkoutPeople() throws {
        let context = try makeContext()
        let person = Person(name: "Alex")
        let entry = LogEntry(
            kind: .workout,
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 2_000),
            timeConfidence: .explicit,
            needsReview: false
        )
        entry.workoutDetails = WorkoutDetails(
            healthKitWorkoutUUID: UUID(),
            activityTypeRawValue: 20,
            activityName: "Functional Strength Training",
            movementKind: .staticWorkout,
            activeEnergyKilocalories: 180
        )

        context.insert(person)
        context.insert(entry)
        try context.save()

        let model = WorkoutPlaceReviewModel(entry: entry)
        model.togglePerson(person.id)
        let didSave = model.save(
            entry: entry,
            places: [],
            people: [person],
            in: context
        )

        #expect(didSave)
        #expect(entry.people.map(\.id) == [person.id])
        #expect(entry.startTime == Date(timeIntervalSince1970: 1_000))
        #expect(entry.endTime == Date(timeIntervalSince1970: 2_000))
        #expect(entry.workoutDetails?.activeEnergyKilocalories == 180)
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
