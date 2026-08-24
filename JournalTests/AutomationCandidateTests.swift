import Foundation
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
        #expect(TimelineEntrySnapshot(entry: entry).destination == "5th Avenue, New York")
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
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return ModelContext(container)
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
}
