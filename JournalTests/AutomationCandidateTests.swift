import Foundation
import SQLite3
import SwiftData
import Testing

@testable import Journal

@Suite("Automation candidates")
@MainActor
struct AutomationCandidateTests {
    @Test("An open visit is updated and only appears after departure")
    func openVisitClosure() throws {
        let context = try makeContext()
        let arrival = Date(timeIntervalSince1970: 1_800_000_000)
        let open = visit(arrival: arrival)

        let storedOpen = try AutomationCandidateStore.upsertVisit(
            open,
            in: context
        )
        let candidate = try #require(storedOpen)
        try context.save()
        #expect(candidate.endTime == nil)
        #expect(AutomationCandidateSnapshot(candidate) == nil)

        let departure = arrival.addingTimeInterval(3_600)
        let closed = visit(arrival: arrival, departure: departure)
        let storedClosed = try AutomationCandidateStore.upsertVisit(
            closed,
            in: context
        )
        let updated = try #require(storedClosed)
        try context.save()

        #expect(updated.id == candidate.id)
        #expect(updated.endTime == departure)
        #expect(AutomationCandidateSnapshot(updated) != nil)
        #expect(try context.fetch(
            FetchDescriptor<AutomationCandidate>()
        ).count == 1)
    }

    @Test("Handled detections remain handled during reconciliation")
    func handledVisitDoesNotReturn() throws {
        let context = try makeContext()
        let arrival = Date(timeIntervalSince1970: 1_800_000_000)
        let detection = visit(
            arrival: arrival,
            departure: arrival.addingTimeInterval(1_800)
        )
        let storedCandidate = try AutomationCandidateStore.upsertVisit(
            detection,
            in: context
        )
        let candidate = try #require(storedCandidate)
        try AutomationCandidateStore.dismiss(candidate, in: context)

        let storedReconciliation = try AutomationCandidateStore.upsertVisit(
            detection,
            in: context
        )
        let reconciled = try #require(storedReconciliation)
        #expect(reconciled.id == candidate.id)
        #expect(reconciled.status == .dismissed)
        #expect(AutomationCandidateSnapshot(reconciled) == nil)
    }

    @Test("Dismissing a candidate removes its materialized entry immediately")
    func dismissRemovesMaterializedEntry() throws {
        let context = try makeJournalContext()
        let arrival = Date(timeIntervalSince1970: 1_800_000_000)
        let storedCandidate = try AutomationCandidateStore.upsertVisit(
            visit(
                arrival: arrival,
                departure: arrival.addingTimeInterval(1_800)
            ),
            in: context
        )
        let candidate = try #require(storedCandidate)
        try context.save()
        try AutomationCandidateEntryService.synchronizePending(in: context)
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).count == 1)

        try AutomationCandidateStore.dismiss(candidate, in: context)

        #expect(candidate.status == .dismissed)
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).isEmpty)
    }

    @Test("Quick accepting a transit keeps its materialized entry in place")
    func quickAcceptTransitKeepsMaterializedEntry() throws {
        let context = try makeJournalContext()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let candidate = AutomationCandidate(
            sourceFingerprint: "quick-accept-transit",
            kind: .transit,
            startTime: start,
            endTime: start.addingTimeInterval(900),
            motionKind: .walk,
            motionConfidenceRawValue: 2,
            originLocation: Location(latitude: 44.43, longitude: 26.10),
            destinationLocation: Location(latitude: 44.44, longitude: 26.11)
        )
        context.insert(candidate)
        try context.save()
        try AutomationCandidateEntryService.synchronizePending(in: context)

        let entry = try #require(
            try context.fetch(FetchDescriptor<LogEntry>()).first
        )
        let entryID = entry.id
        #expect(entry.needsReview)
        #expect(entry.transitDetails?.fieldReviews.isEmpty == false)

        let acceptedID = try AutomationCandidateStore
            .acceptMaterializedTransit(
                candidateID: candidate.id,
                entryID: entryID,
                in: context
            )

        #expect(acceptedID == entryID)
        #expect(candidate.status == .accepted)
        #expect(candidate.acceptedEntryID == entryID)
        #expect(entry.automationCandidateID == candidate.id)
        #expect(!entry.needsReview)
        #expect(entry.transitDetails?.fieldReviews.isEmpty == true)
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).count == 1)
        #expect(
            try AutomationCandidateEntryService.synchronizePending(
                in: context
            ) == 0
        )
    }

    @Test("Invalid visit intervals are ignored")
    func invalidVisits() throws {
        let context = try makeContext()
        let arrival = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(try AutomationCandidateStore.upsertVisit(
            visit(arrival: .distantPast),
            in: context
        ) == nil)
        #expect(try AutomationCandidateStore.upsertVisit(
            visit(
                arrival: arrival,
                departure: arrival.addingTimeInterval(-1)
            ),
            in: context
        ) == nil)
    }

    @Test("Accepted motion detections remain idempotent")
    func acceptedMotionDoesNotReturn() throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let detection = MotionTransitDetection(
            kind: .bicycle,
            confidenceRawValue: 2,
            startTime: start,
            endTime: start.addingTimeInterval(900),
            originLocation: Location(latitude: 44.42, longitude: 26.10),
            originPlaceID: nil,
            destinationLocation: Location(
                latitude: 44.45,
                longitude: 26.13
            ),
            destinationPlaceID: nil
        )
        let storedCandidate = try AutomationCandidateStore.upsertMotion(
            detection,
            in: context
        )
        let candidate = try #require(storedCandidate)
        AutomationCandidateStore.markAccepted(candidate, entryID: UUID())
        try context.save()

        let storedReconciliation = try AutomationCandidateStore.upsertMotion(
            detection,
            in: context
        )
        let reconciled = try #require(storedReconciliation)
        #expect(reconciled.id == candidate.id)
        #expect(reconciled.status == .accepted)
        #expect(try context.fetch(
            FetchDescriptor<AutomationCandidate>()
        ).count == 1)
    }

    @Test("Pending motion reconciliation promotes saved endpoint identities")
    func pendingMotionEndpointPromotion() throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let homeID = UUID()
        let officeID = UUID()
        let initial = MotionTransitDetection(
            kind: .walk,
            confidenceRawValue: 1,
            startTime: start,
            endTime: start.addingTimeInterval(900),
            originLocation: Location(latitude: 44.43, longitude: 26.10),
            originPlaceID: nil,
            destinationLocation: Location(latitude: 44.44, longitude: 26.11),
            destinationPlaceID: nil
        )
        let candidate = try #require(
            try AutomationCandidateStore.upsertMotion(initial, in: context)
        )
        try context.save()

        let enriched = MotionTransitDetection(
            kind: .walk,
            confidenceRawValue: 2,
            startTime: start,
            endTime: start.addingTimeInterval(900),
            originLocation: Location(latitude: 44.431, longitude: 26.101),
            originPlaceID: homeID,
            destinationLocation: Location(latitude: 44.441, longitude: 26.111),
            destinationPlaceID: officeID
        )
        let reconciled = try #require(
            try AutomationCandidateStore.upsertMotion(enriched, in: context)
        )

        #expect(reconciled.id == candidate.id)
        #expect(reconciled.originPlaceID == homeID)
        #expect(reconciled.destinationPlaceID == officeID)
        #expect(reconciled.originLocation == enriched.originLocation)
        #expect(reconciled.destinationLocation == enriched.destinationLocation)
        #expect(reconciled.motionConfidenceRawValue == 2)
    }

    @Test("Pending candidates materialize once with endpoint metadata")
    func pendingCandidateMaterialization() throws {
        let context = try makeJournalContext()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let candidate = AutomationCandidate(
            sourceFingerprint: "motion-materialization",
            kind: .transit,
            startTime: start,
            endTime: start.addingTimeInterval(3_600),
            timeZoneIdentifier: "Europe/London",
            motionKind: .automotive,
            motionConfidenceRawValue: 2,
            originLocation: Location(
                latitude: 51.50,
                longitude: -0.12,
                formattedAddress: "Whitehall, London",
                timeZoneIdentifier: "Europe/London"
            ),
            destinationLocation: Location(
                latitude: 40.76,
                longitude: -73.98,
                formattedAddress: "5th Avenue, New York",
                timeZoneIdentifier: "America/New_York"
            )
        )
        context.insert(candidate)
        try context.save()

        #expect(
            try AutomationCandidateEntryService.synchronizePending(
                in: context
            ) == 1
        )
        #expect(
            try AutomationCandidateEntryService.synchronizePending(
                in: context
            ) == 0
        )

        let entries = try context.fetch(FetchDescriptor<LogEntry>())
        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(entry.id == candidate.id)
        #expect(entry.automationCandidateID == candidate.id)
        #expect(entry.needsReview)
        #expect(entry.startTimeZoneIdentifier == "Europe/London")
        #expect(entry.endTimeZoneIdentifier == "America/New_York")
        #expect(TimelineEntrySnapshot(entry: entry).destination == "5th Avenue")
    }

    @Test("Pending transit entries retroactively adopt adjacent saved places")
    func materializedTransitEndpointPromotion() throws {
        let context = try makeJournalContext()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(30 * 60)
        let candidate = AutomationCandidate(
            sourceFingerprint: "retroactive-endpoint-place-promotion",
            kind: .transit,
            startTime: start,
            endTime: end,
            motionKind: .walk,
            motionConfidenceRawValue: 2,
            originLocation: Location(
                latitude: 44.43,
                longitude: 26.10,
                formattedAddress: "Detected home address"
            ),
            destinationLocation: Location(
                latitude: 44.44,
                longitude: 26.11,
                formattedAddress: "Detected office address"
            )
        )
        context.insert(candidate)
        try context.save()
        try AutomationCandidateEntryService.synchronizePending(in: context)

        let home = Place(
            name: "Home",
            location: Location(latitude: 44.431, longitude: 26.101),
            accuracyRadiusMeters: 200
        )
        let office = Place(
            name: "Office",
            location: Location(latitude: 44.441, longitude: 26.111),
            accuracyRadiusMeters: 200
        )
        let previousVisit = LogEntry(
            kind: .placeVisit,
            startTime: start.addingTimeInterval(-3_600),
            endTime: start,
            needsReview: false
        )
        previousVisit.placeVisitDetails = PlaceVisitDetails(place: home)
        let nextVisit = LogEntry(
            kind: .placeVisit,
            startTime: end,
            endTime: end.addingTimeInterval(3_600),
            needsReview: false
        )
        nextVisit.placeVisitDetails = PlaceVisitDetails(place: office)
        context.insert(home)
        context.insert(office)
        context.insert(previousVisit)
        context.insert(nextVisit)
        try context.save()

        try AutomationCandidateEntryService.synchronizePending(in: context)

        let candidateID = candidate.id
        let transit = try #require(try context.fetch(
            FetchDescriptor<LogEntry>(
                predicate: #Predicate { $0.id == candidateID }
            )
        ).first)
        #expect(candidate.originPlaceID == home.id)
        #expect(candidate.destinationPlaceID == office.id)
        #expect(transit.transitDetails?.originPlace?.id == home.id)
        #expect(transit.transitDetails?.destinationPlace?.id == office.id)
        #expect(TimelineEntrySnapshot(entry: transit).origin == "Home")
        #expect(TimelineEntrySnapshot(entry: transit).destination == "Office")

        let day = TimelineDayKey(date: start, timeZone: .current)
        let projection = TimelineProjection.project(
            entries: [previousVisit, transit, nextVisit].map(
                TimelineEntrySnapshot.init(entry:)
            ),
            for: day
        )
        let transitPresentation = try #require(
            projection.rows.first {
                $0.occurrence.entryID == transit.id
            }?.transitPresentation
        )
        #expect(!transitPresentation.origin.showsPseudoEntry)
        #expect(!transitPresentation.destination.showsPseudoEntry)
    }

    @Test("Established moving entries suppress pending transit materialization")
    func establishedMovementSuppressesTransit() throws {
        let context = try makeJournalContext()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let workout = LogEntry(
            kind: .workout,
            startTime: start,
            endTime: start.addingTimeInterval(30 * 60),
            needsReview: false
        )
        workout.workoutDetails = WorkoutDetails(
            healthKitWorkoutUUID: UUID(),
            activityTypeRawValue: 0,
            activityName: "Walking",
            movementKind: .moving
        )
        let candidate = motionCandidate(
            fingerprint: "covered-motion",
            start: start.addingTimeInterval(2 * 60),
            end: start.addingTimeInterval(28 * 60)
        )
        context.insert(workout)
        context.insert(candidate)
        try context.save()

        #expect(
            try AutomationCandidateEntryService.synchronizePending(in: context)
                == 0
        )
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).count == 1)
        #expect(candidate.status == .pending)
        #expect(AutomationCandidateSnapshot(candidate) != nil)
    }

    @Test("Duplicate suppression removes an existing review entry retroactively")
    func establishedMovementRemovesMaterializedTransit() throws {
        let context = try makeJournalContext()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let candidate = motionCandidate(
            fingerprint: "retroactive-covered-motion",
            start: start,
            end: start.addingTimeInterval(20 * 60)
        )
        context.insert(candidate)
        try context.save()
        try AutomationCandidateEntryService.synchronizePending(in: context)
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).count == 1)

        let workout = LogEntry(
            kind: .workout,
            startTime: start,
            endTime: start.addingTimeInterval(20 * 60),
            needsReview: false
        )
        workout.workoutDetails = WorkoutDetails(
            healthKitWorkoutUUID: UUID(),
            activityTypeRawValue: 0,
            activityName: "Walking",
            movementKind: .moving
        )
        context.insert(workout)
        try context.save()

        try AutomationCandidateEntryService.synchronizePending(in: context)

        let entries = try context.fetch(FetchDescriptor<LogEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.id == workout.id)
        #expect(candidate.status == .pending)
    }

    @Test("Established place entries suppress pending visit materialization")
    func establishedPlaceSuppressesVisitMaterialization() throws {
        let context = try makeJournalContext()
        let start = Date(timeIntervalSinceReferenceDate: 18_000)
        let end = start.addingTimeInterval(30 * 60)
        let placeEntry = LogEntry(
            kind: .placeVisit,
            startTime: start,
            endTime: end,
            startTimeZoneIdentifier: "Europe/Bucharest",
            endTimeZoneIdentifier: "Europe/Bucharest",
            needsReview: false
        )
        placeEntry.placeVisitDetails = PlaceVisitDetails(
            location: Location(latitude: 45.65, longitude: 25.60)
        )
        let candidate = AutomationCandidate(
            sourceFingerprint: "visit-established-overlap",
            kind: .visit,
            startTime: start.addingTimeInterval(2 * 60),
            endTime: end.addingTimeInterval(-2 * 60),
            visitLocation: Location(latitude: 45.65, longitude: 25.60)
        )
        context.insert(placeEntry)
        context.insert(candidate)
        try context.save()

        let inserted = try AutomationCandidateEntryService.synchronizePending(
            in: context
        )

        #expect(inserted == 0)
        let entries = try context.fetch(FetchDescriptor<LogEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.id == placeEntry.id)
        #expect(candidate.status == .pending)
    }

    @Test("Candidate boundaries snap to established entries within five minutes")
    func establishedBoundarySnapping() throws {
        let context = try makeJournalContext()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let establishedStart = start.addingTimeInterval(14 * 60)
        let visit = LogEntry(
            kind: .placeVisit,
            startTime: establishedStart,
            endTime: start.addingTimeInterval(45 * 60),
            needsReview: false
        )
        visit.placeVisitDetails = PlaceVisitDetails(
            location: Location(latitude: 44.43, longitude: 26.10)
        )
        let transit = motionCandidate(
            fingerprint: "snap-to-established",
            start: start,
            end: start.addingTimeInterval(16 * 60)
        )
        context.insert(visit)
        context.insert(transit)
        try context.save()

        try AutomationCandidateEntryService.synchronizePending(in: context)

        #expect(transit.endTime == establishedStart)
        let transitID = transit.id
        let materialized = try #require(try context.fetch(
            FetchDescriptor<LogEntry>(
                predicate: #Predicate { $0.id == transitID }
            )
        ).first)
        #expect(materialized.endTime == establishedStart)
    }

    @Test("Motion transit boundaries take precedence over visit suggestions")
    func motionBoundarySnapsVisitCandidate() throws {
        let context = try makeJournalContext()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let transitEnd = start.addingTimeInterval(16 * 60)
        let transit = motionCandidate(
            fingerprint: "motion-source-of-truth",
            start: start,
            end: transitEnd
        )
        let visit = AutomationCandidate(
            sourceFingerprint: "visit-near-motion",
            kind: .visit,
            startTime: start.addingTimeInterval(14 * 60),
            endTime: start.addingTimeInterval(45 * 60),
            visitLocation: Location(latitude: 44.44, longitude: 26.11)
        )
        context.insert(transit)
        context.insert(visit)
        try context.save()

        try AutomationCandidateEntryService.synchronizePending(in: context)

        #expect(transit.endTime == transitEnd)
        #expect(visit.startTime == transitEnd)
    }

    @Test("A multi-day candidate remains reviewable away from its start day")
    func multiDayCandidateReviewRouting() throws {
        let context = try makeJournalContext()
        let zone = try #require(TimeZone(identifier: "Europe/Bucharest"))
        let start = Calendar(identifier: .gregorian).date(
            from: DateComponents(
                timeZone: zone,
                year: 2026,
                month: 8,
                day: 20,
                hour: 22
            )
        )!
        let candidate = AutomationCandidate(
            sourceFingerprint: "multi-day-review-routing",
            kind: .visit,
            startTime: start,
            endTime: start.addingTimeInterval(30 * 60 * 60),
            timeZoneIdentifier: zone.identifier,
            visitLocation: Location(
                latitude: 44.43,
                longitude: 26.10,
                timeZoneIdentifier: zone.identifier
            )
        )
        context.insert(candidate)
        try context.save()
        try AutomationCandidateEntryService.synchronizePending(in: context)

        let followingDay = TimelineDayKey(
            date: start.addingTimeInterval(24 * 60 * 60),
            timeZone: zone
        )
        let presentation = HomePresentationModel()
        presentation.reloadTimeline(for: followingDay, in: context)

        #expect(presentation.automationCandidates.isEmpty)
        #expect(
            presentation.pendingAutomationCandidate(forEntryID: candidate.id)?.id
                == candidate.id
        )
    }

    @Test("Timeline names fall back to detected endpoint text")
    func endpointRawTextFallback() {
        let entry = LogEntry(
            kind: .transit,
            startTime: .now,
            endTime: .now.addingTimeInterval(600),
            needsReview: true
        )
        entry.transitDetails = TransitDetails(
            type: "Car",
            originRawText: "Detected origin address",
            destinationRawText: "Detected destination address"
        )

        let snapshot = TimelineEntrySnapshot(entry: entry)
        #expect(snapshot.origin == "Detected origin address")
        #expect(snapshot.destination == "Detected destination address")
    }

    @Test("Previously accepted entries receive automation provenance")
    func acceptedEntryProvenanceBackfill() throws {
        let context = try makeJournalContext()
        let entry = LogEntry(
            kind: .placeVisit,
            startTime: .now,
            endTime: .now.addingTimeInterval(600),
            needsReview: false
        )
        entry.placeVisitDetails = PlaceVisitDetails(
            location: Location(latitude: 44.43, longitude: 26.10)
        )
        let candidate = AutomationCandidate(
            sourceFingerprint: "accepted-provenance",
            kind: .visit,
            status: .accepted,
            startTime: entry.startTime ?? .now,
            endTime: entry.endTime,
            acceptedEntryID: entry.id
        )
        context.insert(entry)
        context.insert(candidate)
        try context.save()

        #expect(
            try AutomationCandidateEntryService.synchronizePending(
                in: context
            ) == 0
        )
        #expect(entry.automationCandidateID == candidate.id)
    }

    @Test("Accepting a review updates the existing detail model in place")
    func acceptancePreservesDetailIdentity() async throws {
        let context = try makeJournalContext()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let candidate = AutomationCandidate(
            sourceFingerprint: "visit-in-place-acceptance",
            kind: .visit,
            startTime: start,
            endTime: start.addingTimeInterval(1_800),
            visitLocation: Location(latitude: 44.43, longitude: 26.10)
        )
        let person = Person(name: "Alex")
        context.insert(person)
        context.insert(candidate)
        try context.save()
        try AutomationCandidateEntryService.synchronizePending(in: context)

        let storedEntry = try #require(
            try context.fetch(FetchDescriptor<LogEntry>()).first
        )
        let originalDetails = try #require(storedEntry.placeVisitDetails)
        let originalDetailsID = originalDetails.persistentModelID
        let model = AutomationCandidateReviewModel()
        let draft = try #require(
            model.makeDraft(
                candidate: candidate,
                places: [],
                materializedEntry: storedEntry
            )
        )
        let newEnd = start.addingTimeInterval(2_700)
        draft.endTime = newEnd
        draft.placeVisitDetails?.placeRawText = "Edited place"
        let session = EntryDetailEditSession(entry: draft)
        session.selectedPeopleIDs = [person.id]
        try EntryDetailEditingService.savePeople(
            entry: draft,
            session: session,
            people: [person],
            in: context,
            persist: false
        )
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).count == 1)

        #expect(await model.commit(
            draft,
            selectedPeopleIDs: session.selectedPeopleIDs,
            candidate: candidate,
            in: context,
            performEnrichment: false
        ))

        let entries = try context.fetch(FetchDescriptor<LogEntry>())
        let acceptedEntry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(acceptedEntry.endTime == newEnd)
        #expect(acceptedEntry.placeVisitDetails?.persistentModelID == originalDetailsID)
        #expect(acceptedEntry.placeVisitDetails?.placeRawText == "Edited place")
        #expect(originalDetails.placeRawText == "Edited place")
        #expect(acceptedEntry.people.map(\.id) == [person.id])
        #expect(candidate.status == .accepted)
    }

    @Test("Startup repair recovers an accepted entry with a dangling detail link")
    func startupRepairRecoversDanglingAcceptedEntry() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "journal.store")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let entryID = try populateAcceptedVisitStore(
            at: storeURL,
            start: start
        )
        try deleteAllPlaceVisitDetailRows(at: storeURL)

        #expect(
            try SwiftDataStoreIntegrityRepair
                .clearDanglingEntryDetailReferences(at: storeURL) == 1
        )

        let context = try makePersistentJournalContext(at: storeURL)
        let entry = try #require(try context.fetch(
            FetchDescriptor<LogEntry>(
                predicate: #Predicate { $0.id == entryID }
            )
        ).first)
        #expect(entry.placeVisitDetails == nil)

        try AutomationCandidateStoreRepair.repairAcceptedEntries(in: context)

        #expect(entry.startTime == start)
        #expect(entry.endTime == start.addingTimeInterval(2_700))
        #expect(entry.placeVisitDetails?.location?.latitude == 44.43)
        #expect(entry.placeVisitDetails?.location?.longitude == 26.10)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([AutomationCandidate.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return ModelContext(container)
    }

    private func makeJournalContext() throws -> ModelContext {
        ModelContext(try makeJournalContainer())
    }

    private func makeJournalContainer(
        configuration: ModelConfiguration = ModelConfiguration(
            isStoredInMemoryOnly: true
        )
    ) throws -> ModelContainer {
        let schema = Schema([
            LogEntry.self,
            Person.self,
            Place.self,
            TransitDetails.self,
            PlaceVisitDetails.self,
            WorkoutDetails.self,
            TransitType.self,
            AutomationCandidate.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    private func makePersistentJournalContext(
        at storeURL: URL
    ) throws -> ModelContext {
        let schema = Schema([
            LogEntry.self,
            Person.self,
            Place.self,
            TransitDetails.self,
            PlaceVisitDetails.self,
            WorkoutDetails.self,
            TransitType.self,
            AutomationCandidate.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL
        )
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [configuration]
        ))
    }

    private func populateAcceptedVisitStore(
        at storeURL: URL,
        start: Date
    ) throws -> UUID {
        let context = try makePersistentJournalContext(at: storeURL)
        let candidate = AutomationCandidate(
            sourceFingerprint: "dangling-accepted-visit",
            kind: .visit,
            status: .accepted,
            startTime: start,
            endTime: start.addingTimeInterval(1_800),
            visitLocation: Location(latitude: 44.43, longitude: 26.10)
        )
        let entry = LogEntry(
            kind: .placeVisit,
            startTime: start,
            endTime: start.addingTimeInterval(2_700),
            automationCandidateID: candidate.id,
            needsReview: false
        )
        entry.placeVisitDetails = PlaceVisitDetails(
            location: Location(latitude: 44.44, longitude: 26.11)
        )
        candidate.acceptedEntryID = entry.id
        context.insert(candidate)
        context.insert(entry)
        try context.save()
        return entry.id
    }

    private func deleteAllPlaceVisitDetailRows(at storeURL: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            storeURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            throw NSError(domain: "AutomationCandidateTests", code: 1)
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(
            database,
            "DELETE FROM ZPLACEVISITDETAILS",
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw NSError(domain: "AutomationCandidateTests", code: 2)
        }
    }

    private func visit(
        arrival: Date,
        departure: Date? = nil
    ) -> VisitDetectionSnapshot {
        VisitDetectionSnapshot(
            arrivalDate: arrival,
            departureDate: departure,
            latitude: 44.4268,
            longitude: 26.1025,
            horizontalAccuracyMeters: 50
        )
    }


    private func motionCandidate(
        fingerprint: String,
        start: Date,
        end: Date
    ) -> AutomationCandidate {
        AutomationCandidate(
            sourceFingerprint: fingerprint,
            kind: .transit,
            startTime: start,
            endTime: end,
            motionKind: .walk,
            motionConfidenceRawValue: 2,
            originLocation: Location(latitude: 44.42, longitude: 26.10),
            destinationLocation: Location(latitude: 44.45, longitude: 26.13)
        )
    }
}
