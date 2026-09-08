import Foundation
import SwiftData

// References to the live types must live outside the historical schema scopes.
enum JournalSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [LogEntry.self, Person.self, Place.self, TransitDetails.self,
         PlaceVisitDetails.self, WorkoutDetails.self, TransitType.self,
         AutomationCandidate.self, ActiveJournalRecording.self]
    }
}

enum JournalSchemaMigration: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [JournalSchemaV1.self, JournalSchemaV2.self, JournalSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .custom(
                fromVersion: JournalSchemaV1.self,
                toVersion: JournalSchemaV2.self,
                willMigrate: nil,
                didMigrate: { context in
                    let encoder = JSONEncoder()
                    for details in try context.fetch(FetchDescriptor<JournalSchemaV2.TransitDetails>()) {
                        details.originLocationPayload = try details.originLocation.map(encoder.encode)
                        details.destinationLocationPayload = try details.destinationLocation.map(encoder.encode)
                    }
                    for details in try context.fetch(FetchDescriptor<JournalSchemaV2.PlaceVisitDetails>()) {
                        details.locationPayload = try details.location.map(encoder.encode)
                    }
                    for details in try context.fetch(FetchDescriptor<JournalSchemaV2.WorkoutDetails>()) {
                        details.sourceLocationPayload = try details.sourceLocation.map(encoder.encode)
                        details.originLocationPayload = try details.originLocation.map(encoder.encode)
                        details.destinationLocationPayload = try details.destinationLocation.map(encoder.encode)
                    }
                    for candidate in try context.fetch(FetchDescriptor<JournalSchemaV2.AutomationCandidate>()) {
                        candidate.visitLocationPayload = try candidate.visitLocation.map(encoder.encode)
                        candidate.originLocationPayload = try candidate.originLocation.map(encoder.encode)
                        candidate.destinationLocationPayload = try candidate.destinationLocation.map(encoder.encode)
                    }
                    try context.save()
                }
            ),
            .lightweight(fromVersion: JournalSchemaV2.self, toVersion: JournalSchemaV3.self),
        ]
    }
}
