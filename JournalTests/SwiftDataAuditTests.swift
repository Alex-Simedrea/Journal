import Foundation
import Observation
import SwiftData
import Testing

@testable import Journal

@MainActor
@Suite("SwiftData audit", .serialized)
struct SwiftDataAuditTests {
    private var models: [any PersistentModel.Type] {
        [LogEntry.self, Person.self, Place.self, TransitDetails.self,
         PlaceVisitDetails.self, WorkoutDetails.self, TransitType.self,
         AutomationCandidate.self, ActiveJournalRecording.self]
    }

    @Test("Existing disk stores preserve optional locations and recorded collections")
    func legacyStoreMigration() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "journal.store")
        try writeLegacyStore(at: url)

        let schema = Schema(models)
        let container = try ModelContainer(
            for: schema, migrationPlan: JournalSchemaMigration.self,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        let context = container.mainContext
        let entries = try context.fetch(FetchDescriptor<LogEntry>())
        #expect(entries.count == 3)
        let transit = try #require(entries.first { $0.kind == .transit }?.transitDetails)
        #expect(transit.originLocation == nil)
        #expect(transit.destinationLocation?.latitude == 44.4)
        #expect(transit.destinationPlace?.name == "Airport")
        #expect(transit.originCandidates.isEmpty)
        #expect(transit.destinationCandidates.first?.name == "Terminal")
        #expect(transit.recordedRoute.count == 1)
        #expect(transit.recordedMotion.first?.kind == .automotive)
        let visit = try #require(entries.first { $0.kind == .placeVisit }?.placeVisitDetails)
        #expect(visit.location?.longitude == 26.1)
        #expect(visit.candidates.isEmpty)
        let workout = try #require(entries.first { $0.kind == .workout }?.workoutDetails)
        #expect(workout.sourceLocation == nil)
        #expect(workout.originLocation?.latitude == 44.4)
        #expect(workout.destinationLocation == nil)
        let candidate = try #require(context.fetch(FetchDescriptor<AutomationCandidate>()).first)
        #expect(candidate.visitLocation?.latitude == 44.4)
        #expect(candidate.originLocation == nil)
        let recording = try #require(context.fetch(FetchDescriptor<ActiveJournalRecording>()).first)
        #expect(recording.points.count == 1)
        #expect(recording.points.first?.altitude == nil)
        #expect(entries.first { $0.kind == .transit }?.people.first?.name == "Test Person")

        // Nil ↔ value transitions and observation must remain safe after migration.
        withObservationTracking {
            _ = transit.originLocation
            _ = workout.destinationLocation
            _ = candidate.originLocation
        } onChange: {}
        transit.originLocation = visit.location
        workout.destinationLocation = visit.location
        candidate.originLocation = visit.location
        try context.save()
        let reader = ModelContext(container)
        #expect(try reader.fetch(FetchDescriptor<TransitDetails>()).first?.originLocation?.latitude == 44.4)
    }

    private func memoryContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(models), configurations: [
            ModelConfiguration(isStoredInMemoryOnly: true)
        ])
    }

    @Test("Cached services retain their container as well as the context")
    func persistenceContainerLifetime() async throws {
        weak var retainedContainer: ModelContainer?
        func makeService() async throws -> HomeFeedProjectionStore {
            let container = try memoryContainer()
            retainedContainer = container
            return await JournalPersistenceServices.shared.homeFeed(for: container)
        }
        let service = try await makeService()
        #expect(retainedContainer != nil)
        #expect(service.modelContainer === retainedContainer)
        #expect(try await service.load().snapshots.isEmpty)
    }

    @Test("Review drafts never enter the live graph, and confirmation resolves saved identities")
    func detachedReviewGraph() throws {
        let container = try memoryContainer()
        let context = container.mainContext
        let place = Place(name: "Library", location: Location(latitude: 44, longitude: 26))
        let person = Person(name: "Reader")
        context.insert(place)
        context.insert(person)
        try context.save()
        let draft = PlaceVisitEntryStore.makeEntry(draft: .init(
            place: place, location: place.location, placeRawText: place.name,
            startTime: .now.addingTimeInterval(-3600), endTime: .now,
            timeConfidence: .explicit, people: [person], candidates: [],
            unresolvedPeople: [], fieldReviews: [], entryKindReviewReason: nil
        ), rawInput: nil, detachedRelationships: true)
        #expect(draft.modelContext == nil)
        #expect(draft.placeVisitDetails?.place !== place)
        #expect(draft.people.first !== person)
        draft.placeVisitDetails?.place?.name = "Draft only"
        // An unrelated write must not persist any part of a cancelled review.
        person.name = "Updated reader"
        try context.save()
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PlaceVisitDetails>()).isEmpty)
        #expect(person.entries.isEmpty)
        #expect(place.name == "Library")

        let committed = try EntryDraftGraph.materialize(
            draft, selectedPeopleIDs: [person.id], in: context
        )
        try PlaceVisitEntryStore.insert(committed, in: context)
        #expect(committed !== draft)
        #expect(committed.placeVisitDetails?.place === place)
        #expect(committed.people.first === person)
        #expect(draft.modelContext == nil)
        #expect(try context.fetch(FetchDescriptor<Place>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Person>()).count == 1)
    }

    @Test("Review people survive location, time, photo, and metadata confirmations")
    func reviewPeopleSurviveOtherEditors() throws {
        let container = try memoryContainer()
        let context = container.mainContext
        let person = try EntryDetailEditingService.createPerson(name: "Friend", in: context)
        let draft = LogEntry(kind: .transit, startTime: .now.addingTimeInterval(-3600), endTime: .now, needsReview: true)
        draft.transitDetails = TransitDetails(type: "Train")
        let coordinator = EntryDetailCoordinator(entry: draft)
        coordinator.present(.people)
        coordinator.session.selectedPeopleIDs = [person.id]
        try EntryDetailEditingService.savePeople(entry: draft, session: coordinator.session,
            people: [], in: context, persist: false)
        coordinator.returnToDetails(entry: draft)
        #expect(coordinator.session.selectedPeopleIDs == [person.id])
        coordinator.present(.location(.origin))
        coordinator.session.setSelection(EntryLocationSelection(
            location: Location(latitude: 44, longitude: 26)), for: .origin)
        try EntryDetailEditingService.saveLocation(entry: draft, role: .origin,
            session: coordinator.session, places: [], in: context, persist: false)
        coordinator.returnToLocations(entry: draft)
        #expect(coordinator.session.selectedPeopleIDs == [person.id])
        try EntryDetailEditingService.saveTime(entry: draft, session: coordinator.session,
            in: context, persist: false)
        coordinator.returnToDetails(entry: draft)
        try EntryDetailEditingService.savePhotos(entry: draft, session: coordinator.session,
            in: context, persist: false)
        coordinator.returnToDetails(entry: draft)
        try EntryDetailEditingService.saveTransitMetadata(entry: draft, session: coordinator.session,
            in: context, persist: false)
        coordinator.returnToDetails(entry: draft)
        #expect(coordinator.session.selectedPeopleIDs == [person.id])
        #expect(draft.people.first?.modelContext == nil)
        #expect(draft.people.first !== person)
        #expect(person.entries.isEmpty)
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).isEmpty)
        coordinator.present(.people)
        coordinator.session.selectedPeopleIDs = []
        coordinator.goBack()
        #expect(coordinator.session.selectedPeopleIDs == [person.id])
    }

    @Test("Saving a new place during review survives acceptance with a previous link")
    func reviewLocationSurvivesAcceptance() async throws {
        let container = try memoryContainer()
        let context = container.mainContext
        let oldLocation = Location(latitude: 44, longitude: 26)
        let newLocation = Location(latitude: 45, longitude: 27)
        let previous = LogEntry(kind: .transit,
            startTime: Date(timeIntervalSince1970: 1000), endTime: Date(timeIntervalSince1970: 2000), needsReview: false)
        previous.transitDetails = TransitDetails(type: "Walk", originLocation: oldLocation,
            destinationLocation: oldLocation)
        let candidate = AutomationCandidate(sourceFingerprint: UUID().uuidString, kind: .visit,
            startTime: Date(timeIntervalSince1970: 2000), endTime: Date(timeIntervalSince1970: 3000),
            visitLocation: oldLocation)
        context.insert(previous)
        context.insert(candidate)
        try context.save()
        let review = AutomationCandidateReviewModel()
        let draft = try #require(review.makeDraft(candidate: candidate, places: []))
        draft.linkedPreviousEntryID = previous.id
        let coordinator = EntryDetailCoordinator(entry: draft)
        coordinator.present(.location(.place))
        coordinator.session.setSelection(EntryLocationSelection(location: newLocation), for: .place)
        coordinator.present(.addPlace(.place))
        let place = try EntryDetailEditingService.createPlace(name: "Chosen place",
            selection: try #require(coordinator.session.selection(for: .place)),
            systemImage: .mappin, in: context)
        coordinator.session.setSelection(EntryLocationSelection(place: place), for: .place)
        coordinator.goBack(discardingChanges: false)
        // @Query may not yet include the newly inserted place.
        try EntryDetailEditingService.saveLocation(entry: draft, role: .place,
            session: coordinator.session, places: [], in: context, persist: false)
        coordinator.returnToDetails(entry: draft)
        #expect(draft.placeVisitDetails?.place?.id == place.id)
        #expect(draft.placeVisitDetails?.location?.latitude == newLocation.latitude)
        #expect(await review.commit(draft, selectedPeopleIDs: [], candidate: candidate,
            in: context, performEnrichment: false))
        let reader = ModelContext(container)
        let saved = try #require(reader.fetch(FetchDescriptor<LogEntry>()).first { $0.id == candidate.id })
        #expect(saved.placeVisitDetails?.place?.id == place.id)
        #expect(saved.placeVisitDetails?.location?.latitude == newLocation.latitude)
        #expect(saved.linkedPreviousEntryID == previous.id)
        #expect(previous.transitDetails?.destinationPlace?.id == place.id)
    }

    @Test("Nested link changes preserve unconfirmed location edits and cancellation")
    func nestedLinksPreserveLocationDraft() {
        let oldLocation = Location(latitude: 44, longitude: 26, timeZoneIdentifier: "Europe/Bucharest")
        let selected = EntryLocationSelection(location: Location(latitude: 51, longitude: 0,
            timeZoneIdentifier: "Europe/London"))
        let entry = LogEntry(kind: .placeVisit, startTimeZoneIdentifier: "Europe/Bucharest",
            endTimeZoneIdentifier: "Europe/Bucharest", needsReview: true)
        entry.placeVisitDetails = PlaceVisitDetails(location: oldLocation)
        let coordinator = EntryDetailCoordinator(entry: entry)
        coordinator.present(.location(.place))
        coordinator.session.setSelection(selected, for: .place)
        coordinator.present(.links)
        entry.linkedPreviousEntryID = UUID()
        coordinator.reloadAfterLinkEdit(entry: entry)
        coordinator.goBack()
        #expect(coordinator.session.selection(for: .place) == selected)
        #expect(coordinator.session.startTimeZoneIdentifier == "Europe/London")
        coordinator.goBack()
        #expect(coordinator.session.selection(for: .place)?.location == oldLocation)
        #expect(coordinator.session.startTimeZoneIdentifier == "Europe/Bucharest")
        #expect(entry.placeVisitDetails?.location == oldLocation)
    }

    @Test("Late location results cannot overwrite selection or a different endpoint")
    func staleLocationPickerResults() async throws {
        var completion: CheckedContinuation<Location, any Error>?
        let picker = EntryLocationPickerModel(currentLocationProvider: {
            try await withCheckedThrowingContinuation { completion = $0 }
        })
        let entry = LogEntry(kind: .transit, needsReview: true)
        entry.transitDetails = TransitDetails(type: "Train")
        let session = EntryDetailEditSession(entry: entry)
        picker.prepare(selection: nil) { session.setSelection($0, for: .origin) }
        let pending = Task { await picker.useCurrentLocation() }
        while completion == nil { await Task.yield() }
        let place = Place(name: "Chosen", location: Location(latitude: 45, longitude: 27))
        picker.select(place)
        // Selection reaches the session synchronously, before another button tap.
        #expect(session.selection(for: .origin)?.placeID == place.id)
        completion?.resume(returning: Location(latitude: 1, longitude: 2))
        #expect(await pending.value == nil)
        #expect(picker.selection?.placeID == place.id)
        #expect(session.selection(for: .origin)?.placeID == place.id)
        completion = nil
        let stopped = Task { await picker.useCurrentLocation() }
        while completion == nil { await Task.yield() }
        picker.stop()
        picker.prepare(selection: nil) { session.setSelection($0, for: .destination) }
        completion?.resume(returning: Location(latitude: 3, longitude: 4))
        #expect(await stopped.value == nil)
        #expect(picker.selection == nil)
        #expect(session.selection(for: .destination) == nil)
        #expect(session.selection(for: .origin)?.placeID == place.id)
        #expect(!picker.isResolving)
    }

    @Test("First import preparation stays detached while library writes and reloads run")
    func firstImportPreparation() async throws {
        let container = try memoryContainer()
        let context = container.mainContext
        let origin = Place(name: "AAA", location: Location(latitude: 44, longitude: 26))
        context.insert(origin)
        try context.save()
        var completion: CheckedContinuation<Location?, Never>?
        let model = BoardingPassReviewModel(pendingImport: PendingBoardingPassImport(
            sourceFingerprint: UUID().uuidString, transitTypeName: "Flight",
            originName: "AAA", originAirportCode: "AAA",
            destinationName: "BBB", destinationAirportCode: "BBB"
        ), airportResolver: { _, _ in
            await withCheckedContinuation { completion = $0 }
        })
        let initial = Task { await model.prepare(places: [origin], transitTypes: []) }
        while completion == nil { await Task.yield() }
        let destination = Place(name: "BBB", location: Location(latitude: 45, longitude: 27))
        context.insert(destination)
        try context.save()
        // Mirrors @Query changing while the first sheet is still preparing.
        await model.prepare(places: [origin, destination], transitTypes: [])
        completion?.resume(returning: Location(latitude: 1, longitude: 2))
        await initial.value
        #expect(model.destinationLocation == nil)
        let draft = model.makeDraftEntry(places: [origin, destination])
        let coordinator = EntryDetailCoordinator(entry: draft)
        #expect(coordinator.session.selection(for: .destination)?.placeID == destination.id)
        #expect(draft.modelContext == nil)
        #expect(draft.transitDetails?.originPlace?.modelContext == nil)
        #expect(draft.transitDetails?.destinationPlace?.modelContext == nil)
        try EntryDetailEditingService.savePhotos(entry: draft, session: coordinator.session,
            in: context, persist: false)
        let service = await JournalPersistenceServices.shared.homeFeed(for: container)
        #expect(try await service.load().snapshots.isEmpty)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TransitDetails>()).isEmpty)
        #expect(origin.name == "AAA")
        #expect(destination.name == "BBB")
    }

    @Test("Repeated import confirmation does not insert another detail graph")
    func repeatedImportConfirmation() async throws {
        let container = try memoryContainer()
        let context = container.mainContext
        let model = BoardingPassReviewModel(pendingImport: PendingBoardingPassImport(
            sourceFingerprint: UUID().uuidString, transitTypeName: "Train",
            originName: "Origin", destinationName: "Destination"
        ))
        let draft = model.makeDraftEntry(places: [])
        #expect(await model.commit(draft, selectedPeopleIDs: [], in: context))
        let first = try #require(context.fetch(FetchDescriptor<LogEntry>()).first)
        let details = first.transitDetails
        #expect(await model.commit(draft, selectedPeopleIDs: [], in: context))
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<TransitDetails>()).count == 1)
        #expect(first.transitDetails === details)
        #expect(draft.modelContext == nil)
    }

    @Test("Photo results cannot write to deleted or changed entries")
    func stalePhotoResults() throws {
        let container = try memoryContainer()
        let context = container.mainContext
        let start = Date.now.addingTimeInterval(-3600)
        let end = Date.now
        let entry = LogEntry(kind: .placeVisit, startTime: start, endTime: end, needsReview: false)
        entry.placeVisitDetails = PlaceVisitDetails(location: Location(latitude: 44, longitude: 26))
        context.insert(entry)
        try context.save()
        let id = entry.id
        let targets = [id: AutomaticPhotoMatchTarget(
            entryID: id, startTime: start, endTime: end,
            geometry: .staticLocation(latitude: 44, longitude: 26, radiusMeters: 250)
        )]
        entry.endTime = end.addingTimeInterval(60)
        try context.save()
        try PhotoAutoLinkService.applyMatches([id: ["stale-photo"]], targets: targets, in: context)
        #expect(entry.photoReferences.isEmpty)
        context.delete(entry)
        try context.save()
        try PhotoAutoLinkService.applyMatches([id: ["deleted-photo"]], targets: targets, in: context)
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).isEmpty)
        #expect(!context.hasChanges)
    }

    @Test("Geocoding can finish after its candidate was deleted")
    func deletedVisitDuringGeocoding() async throws {
        let container = try memoryContainer()
        let context = container.mainContext
        let candidate = AutomationCandidate(
            sourceFingerprint: UUID().uuidString, kind: .visit,
            startTime: .now.addingTimeInterval(-3600), endTime: .now,
            visitLocation: Location(latitude: 44, longitude: 26)
        )
        context.insert(candidate)
        try context.save()
        var resolved = false
        try await VisitMonitoringCoordinator.enrichClosedVisits(in: context) { location in
            resolved = true
            context.delete(candidate)
            try context.save()
            await Task.yield()
            return location
        }
        #expect(resolved)
        #expect(try context.fetch(FetchDescriptor<AutomationCandidate>()).isEmpty)
        #expect(!context.hasChanges)
    }

    @Test("Deletion cannot leave a stale timeline or search route")
    func staleNavigationAndProjection() async throws {
        let container = try memoryContainer()
        let context = container.mainContext
        let entry = LogEntry(kind: .placeVisit, startTime: .now.addingTimeInterval(-3600), endTime: .now, needsReview: false)
        entry.placeVisitDetails = PlaceVisitDetails(location: Location(latitude: 44, longitude: 26))
        context.insert(entry)
        try context.save()
        let id = entry.id
        let home = HomePresentationModel()
        home.reloadTimeline(in: context)
        let search = EntrySearchModel()
        search.load(in: context)
        let store = await JournalPersistenceServices.shared.homeFeed(for: container)
        let snapshot = try await store.load()
        #expect(store.modelContext === context)
        #expect(home.entry(withID: id) === entry)
        try JournalDeletionService.delete(entry, in: context)
        #expect(home.entry(withID: id) == nil)
        #expect(search.entry(withID: id) == nil)
        #expect(snapshot.snapshots.first?.id == id)
        #expect(try await store.load().snapshots.isEmpty)
    }

    @Test("Repeated restore updates matching identities without duplicate graphs")
    func repeatedRestore() throws {
        let container = try memoryContainer()
        let context = container.mainContext
        let person = Person(name: "Reader")
        context.insert(person)
        let entry = LogEntry(kind: .placeVisit, needsReview: false)
        entry.placeVisitDetails = PlaceVisitDetails(location: Location(latitude: 44, longitude: 26))
        entry.people = [person]
        context.insert(entry)
        try context.save()
        let id = entry.id
        let archive = try JournalDataArchiveService.decode(JournalDataArchiveService.exportData(from: context))
        for _ in 0..<3 {
            try JournalDataArchiveService.replaceAllData(with: archive, in: context)
            let saved = try #require(context.fetch(FetchDescriptor<LogEntry>()).first)
            #expect(saved === entry)
            #expect(saved.id == id)
            #expect(saved.people.first === person)
            #expect(try context.fetch(FetchDescriptor<PlaceVisitDetails>()).count == 1)
        }
    }

    private func writeLegacyStore(at url: URL) throws {
        // Intentionally unversioned, exactly as released before this audit.
        let schema = Schema(JournalSchemaV1.models)
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: url)
        ])
        let context = container.mainContext
        let location = Location(latitude: 44.4, longitude: 26.1, displayName: "Terminal")
        let place = JournalSchemaV1.Place(name: "Airport", location: location)
        let person = JournalSchemaV1.Person(name: "Test Person")
        context.insert(place)
        context.insert(person)
        let transit = JournalSchemaV1.LogEntry(kind: .transit, needsReview: false)
        transit.transitDetails = JournalSchemaV1.TransitDetails(
            type: "Car", destinationPlace: place, destinationLocation: location,
            recordedRoute: [.init(latitude: 44.4, longitude: 26.1, timestamp: .now)],
            recordedMotion: [.init(startTime: .now, endTime: .now, kind: .automotive, confidenceRawValue: 2)],
            destinationCandidates: [.init(name: "Terminal", latitude: 44.4, longitude: 26.1)]
        )
        transit.people = [person]
        context.insert(transit)
        let visit = JournalSchemaV1.LogEntry(kind: .placeVisit, needsReview: false)
        visit.placeVisitDetails = JournalSchemaV1.PlaceVisitDetails(location: location)
        context.insert(visit)
        let workout = JournalSchemaV1.LogEntry(kind: .workout, needsReview: false)
        workout.workoutDetails = JournalSchemaV1.WorkoutDetails(
            healthKitWorkoutUUID: UUID(), activityTypeRawValue: 52,
            activityName: "Walking", movementKind: .moving, originLocation: location
        )
        context.insert(workout)
        context.insert(JournalSchemaV1.AutomationCandidate(
            sourceFingerprint: UUID().uuidString, kind: .visit,
            startTime: .now, visitLocation: location
        ))
        context.insert(JournalSchemaV1.ActiveJournalRecording(
            startPath: .foregroundFallback,
            points: [.init(latitude: 44.4, longitude: 26.1, timestamp: .now, horizontalAccuracy: 5)]
        ))
        try context.save()
    }
}
