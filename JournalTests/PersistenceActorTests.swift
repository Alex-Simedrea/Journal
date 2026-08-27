import Foundation
import SwiftData
import Testing

@testable import Journal

@ModelActor
private actor ReviewPersistenceProbe {
    func workoutReviewCounts() throws -> [Int] {
        try modelContext.fetch(FetchDescriptor<WorkoutDetails>()).map {
            $0.fieldReviews.count
        }
    }

    func transitReviewCounts() throws -> [Int] {
        try modelContext.fetch(FetchDescriptor<TransitDetails>()).map {
            $0.fieldReviews.count
        }
    }

    func visitReviewCounts() throws -> [Int] {
        try modelContext.fetch(FetchDescriptor<PlaceVisitDetails>()).map {
            $0.fieldReviews.count
        }
    }
}

@Suite("Persistence actors")
struct PersistenceActorTests {
    @Test("Detached-created model actors do not use the main thread")
    func backgroundModelActorExecutor() async throws {
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
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let actor = await JournalPersistenceActors.shared.maintenance(
            for: JournalModelContainerReference(container)
        )
        #expect(await actor.executorUsesMainThreadForTesting() == false)
    }

    @Test("Review collections materialize on a model actor")
    func reviewCollectionsMaterializeOffMain() async throws {
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
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        context.insert(WorkoutDetails(
            healthKitWorkoutUUID: UUID(),
            activityTypeRawValue: 52,
            activityName: "Walking",
            movementKind: .moving,
            fieldReviews: []
        ))
        context.insert(WorkoutDetails(
            healthKitWorkoutUUID: UUID(),
            activityTypeRawValue: 52,
            activityName: "Walking",
            movementKind: .moving,
            fieldReviews: [
                WorkoutFieldReview(field: .origin, reason: "Review")
            ]
        ))
        context.insert(TransitDetails(type: "Walk", fieldReviews: []))
        context.insert(TransitDetails(
            type: "Walk",
            fieldReviews: [
                TransitFieldReview(field: .destination, reason: "Review")
            ]
        ))
        context.insert(PlaceVisitDetails(fieldReviews: []))
        context.insert(PlaceVisitDetails(fieldReviews: [
            PlaceVisitFieldReview(field: .place, reason: "Review")
        ]))
        try context.save()

        let reference = JournalModelContainerReference(container)
        let probe = await Task.detached {
            ReviewPersistenceProbe(modelContainer: reference.container)
        }.value
        #expect(try await probe.workoutReviewCounts().sorted() == [0, 1])
        #expect(try await probe.transitReviewCounts().sorted() == [0, 1])
        #expect(try await probe.visitReviewCounts().sorted() == [0, 1])
    }

    @Test("Review collections survive a persistent round trip")
    func reviewCollectionsSurvivePersistentRoundTrip() async throws {
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
        let storeDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let storeURL = storeDirectory.appending(path: "journal.store")
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        try insertReviewFixtures(
            schema: schema,
            configuration: configuration
        )

        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let reference = JournalModelContainerReference(container)
        let probe = await Task.detached {
            ReviewPersistenceProbe(modelContainer: reference.container)
        }.value
        #expect(try await probe.workoutReviewCounts().sorted() == [0, 1])
        #expect(try await probe.transitReviewCounts().sorted() == [0, 1])
        #expect(try await probe.visitReviewCounts().sorted() == [0, 1])
    }

    private func insertReviewFixtures(
        schema: Schema,
        configuration: ModelConfiguration
    ) throws {
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        context.insert(WorkoutDetails(
            healthKitWorkoutUUID: UUID(),
            activityTypeRawValue: 52,
            activityName: "Walking",
            movementKind: .moving,
            fieldReviews: []
        ))
        context.insert(WorkoutDetails(
            healthKitWorkoutUUID: UUID(),
            activityTypeRawValue: 52,
            activityName: "Walking",
            movementKind: .moving,
            fieldReviews: [
                WorkoutFieldReview(field: .origin, reason: "Review")
            ]
        ))
        context.insert(TransitDetails(type: "Walk", fieldReviews: []))
        context.insert(TransitDetails(
            type: "Walk",
            fieldReviews: [
                TransitFieldReview(field: .destination, reason: "Review")
            ]
        ))
        context.insert(PlaceVisitDetails(fieldReviews: []))
        context.insert(PlaceVisitDetails(fieldReviews: [
            PlaceVisitFieldReview(field: .place, reason: "Review")
        ]))
        try context.save()
    }
}
