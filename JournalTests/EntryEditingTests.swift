import CoreGraphics
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

    @Test("Focused people save preserves unrelated review fields")
    func peopleSavePreservesOtherReviews() throws {
        let context = try makeContext()
        let person = Person(name: "Emma")
        let entry = LogEntry(
            kind: .transit,
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 2_000),
            needsReview: true
        )
        entry.transitDetails = TransitDetails(
            type: "Bus",
            unresolvedPeople: ["Emma"],
            fieldReviews: [
                TransitFieldReview(field: .people, reason: "Confirm Emma"),
                TransitFieldReview(field: .origin, reason: "Choose origin"),
            ]
        )
        context.insert(person)
        context.insert(entry)
        try context.save()

        let session = EntryDetailEditSession(entry: entry)
        session.selectedPeopleIDs = [person.id]
        try EntryDetailEditingService.savePeople(
            entry: entry,
            session: session,
            people: [person],
            in: context
        )

        #expect(entry.people.map(\.id) == [person.id])
        #expect(entry.transitDetails?.review(for: .people) == nil)
        #expect(entry.transitDetails?.review(for: .origin) != nil)
        #expect(entry.transitDetails?.type == "Bus")
        #expect(entry.needsReview)
    }

    @Test("Backing out restores the active draft without changing the entry")
    func cancelRestoresDraft() {
        let originalStart = Date(timeIntervalSince1970: 1_000)
        let entry = LogEntry(
            kind: .placeVisit,
            startTime: originalStart,
            endTime: Date(timeIntervalSince1970: 2_000),
            needsReview: false
        )
        entry.placeVisitDetails = PlaceVisitDetails()
        let coordinator = EntryDetailCoordinator(entry: entry)

        coordinator.present(.time)
        coordinator.session.startTime = Date(timeIntervalSince1970: 1_500)

        #expect(coordinator.isDirty)
        #expect(entry.startTime == originalStart)
        coordinator.goBack()
        #expect(coordinator.route == .details)
        #expect(coordinator.session.startTime == originalStart)
        #expect(!coordinator.isDirty)

        coordinator.present(.people)
        coordinator.session.selectedPeopleIDs.insert(UUID())
        coordinator.present(.addPerson)
        #expect(coordinator.isDirty)
    }

    @Test("Location derives its time zone and a later manual override persists")
    func derivedAndManualTimeZones() throws {
        let context = try makeContext()
        let entry = LogEntry(
            kind: .placeVisit,
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 2_000),
            creationTimeZoneIdentifier: "UTC",
            needsReview: false
        )
        entry.placeVisitDetails = PlaceVisitDetails()
        context.insert(entry)
        try context.save()

        let session = EntryDetailEditSession(entry: entry)
        session.setSelection(
            EntryLocationSelection(
                location: Location(
                    latitude: 40.71,
                    longitude: -74,
                    timeZoneIdentifier: "America/New_York"
                ),
                title: "New York"
            ),
            for: .place
        )
        #expect(session.startTimeZoneIdentifier == "America/New_York")
        #expect(session.endTimeZoneIdentifier == "America/New_York")

        session.startTimeZoneIdentifier = "Asia/Tokyo"
        session.endTimeZoneIdentifier = "Asia/Tokyo"
        try EntryDetailEditingService.saveTime(
            entry: entry,
            session: session,
            in: context
        )
        #expect(entry.startTimeZoneIdentifier == "Asia/Tokyo")
        #expect(entry.endTimeZoneIdentifier == "Asia/Tokyo")
    }

    @Test("Workout place association preserves immutable HealthKit values")
    func workoutLocationPreservesHealthKitValues() throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let exactOrigin = Location(latitude: 45.1, longitude: 25.1)
        let exactDestination = Location(latitude: 45.2, longitude: 25.2)
        let workoutID = UUID()
        let place = Place(
            name: "Park",
            location: Location(latitude: 45.11, longitude: 25.11),
            systemImage: .park
        )
        let entry = LogEntry(
            kind: .workout,
            startTime: start,
            endTime: end,
            timeConfidence: .explicit,
            needsReview: true
        )
        entry.workoutDetails = WorkoutDetails(
            healthKitWorkoutUUID: workoutID,
            activityTypeRawValue: 37,
            activityName: "Walking",
            movementKind: .moving,
            distanceMeters: 5_300,
            activeEnergyKilocalories: 103,
            originLocation: exactOrigin,
            destinationLocation: exactDestination,
            fieldReviews: [
                WorkoutFieldReview(field: .origin, reason: "Associate place"),
            ]
        )
        context.insert(place)
        context.insert(entry)
        try context.save()

        let session = EntryDetailEditSession(entry: entry)
        session.setSelection(EntryLocationSelection(place: place), for: .origin)
        try EntryDetailEditingService.saveLocation(
            entry: entry,
            role: .origin,
            session: session,
            places: [place],
            in: context
        )

        #expect(entry.workoutDetails?.originPlace?.id == place.id)
        #expect(entry.workoutDetails?.originLocation == exactOrigin)
        #expect(entry.workoutDetails?.destinationLocation == exactDestination)
        #expect(entry.workoutDetails?.healthKitWorkoutUUID == workoutID)
        #expect(entry.workoutDetails?.distanceMeters == 5_300)
        #expect(entry.workoutDetails?.activeEnergyKilocalories == 103)
        #expect(entry.startTime == start)
        #expect(entry.endTime == end)
    }

    @Test("People constellation caps faces and summarizes names")
    func peopleOverflowPresentation() {
        let people = (1...14).map { Person(name: "Person \($0)") }
        let presentation = EntryDetailPeoplePresentation(people: people)

        #expect(presentation.visiblePeople.count == 12)
        #expect(
            presentation.namedPeople.map(\.name)
                == ["Person 1", "Person 2", "Person 3"]
        )
        #expect(presentation.remainingNameCount == 11)
    }

    @Test("People bubbles remain wide, separated, and centered", arguments: 1...12)
    func peopleBubbleGeometry(count: Int) {
        let placements = EntryDetailPeopleConstellationMetrics.placements(
            count: count
        )
        #expect(placements.count == count)
        if count > 1 {
            #expect(Set(placements.map(\.diameter)).count > 1)
        }

        for first in 0..<placements.count {
            for second in (first + 1)..<placements.count {
                let deltaX = placements[second].center.x
                    - placements[first].center.x
                let deltaY = placements[second].center.y
                    - placements[first].center.y
                let distance = hypot(deltaX, deltaY)
                let requiredDistance =
                    (placements[first].diameter
                        + placements[second].diameter) / 2
                    + EntryDetailPeopleConstellationMetrics.gap
                #expect(distance >= requiredDistance - 0.01)
                if count == 3 {
                    #expect(abs(distance - requiredDistance) < 0.01)
                }
            }
        }

        let bounds = placements.reduce(CGRect.null) { bounds, placement in
            bounds.union(
                CGRect(
                    x: placement.center.x - placement.diameter / 2,
                    y: placement.center.y - placement.diameter / 2,
                    width: placement.diameter,
                    height: placement.diameter
                )
            )
        }
        #expect(abs(bounds.midX) < 0.01)
        #expect(abs(bounds.midY) < 0.01)
        #expect(
            bounds.height
                <= EntryDetailPeopleConstellationMetrics.height + 0.01
        )
        #expect(
            bounds.width
                <= EntryDetailPeopleConstellationMetrics.fallbackWidth + 0.01
        )
        if count >= 4 {
            let minimumAspectRatio: CGFloat = switch count {
            case 4: 1.5
            case 6: 1.55
            default: 1.65
            }
            #expect(bounds.width >= bounds.height * minimumAspectRatio)

            for placement in placements {
                let mirroredBubble = placements.contains { candidate in
                    abs(candidate.center.x + placement.center.x) < 0.01
                        && abs(candidate.center.y - placement.center.y) < 0.01
                        && abs(candidate.diameter - placement.diameter) < 0.01
                }
                #expect(mirroredBubble)

                let touchesAtSharedGap = placements.contains { candidate in
                    guard candidate.center != placement.center else {
                        return false
                    }
                    let distance = hypot(
                        candidate.center.x - placement.center.x,
                        candidate.center.y - placement.center.y
                    )
                    let expectedDistance =
                        (candidate.diameter + placement.diameter) / 2
                        + EntryDetailPeopleConstellationMetrics.gap
                    return abs(distance - expectedDistance) < 0.01
                }
                #expect(touchesAtSharedGap)
            }
        }
    }

    @Test("New people and places persist independently of association drafts")
    func independentlyCreatedRecordsPersist() throws {
        let context = try makeContext()
        _ = try EntryDetailEditingService.createPerson(
            name: "  David  ",
            in: context
        )
        let selection = EntryLocationSelection(
            location: Location(latitude: 45.65, longitude: 25.60),
            title: "Reyna Beach"
        )
        _ = try EntryDetailEditingService.createPlace(
            name: "Reyna Beach",
            selection: selection,
            systemImage: .beach,
            in: context
        )

        #expect(try context.fetch(FetchDescriptor<Person>()).map(\.name) == ["David"])
        #expect(try context.fetch(FetchDescriptor<Place>()).map(\.name) == ["Reyna Beach"])
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
