//
//  JournalDeletionService.swift
//  Journal
//

import Foundation
import SwiftData

@MainActor
enum JournalDeletionService {
    static func delete(_ entry: LogEntry, in modelContext: ModelContext) throws {
        let workoutUUID = entry.workoutDetails?.healthKitWorkoutUUID
        if let workoutUUID {
            WorkoutImportPreferences.exclude(workoutUUID)
        }

        do {
            try deleteModel(entry, in: modelContext)
        } catch {
            if let workoutUUID {
                WorkoutImportPreferences.removeExclusion(workoutUUID)
            }
            throw error
        }
    }

    static func delete(_ place: Place, in modelContext: ModelContext) throws {
        try detachReferences(to: place, in: modelContext)
        try deleteModel(place, in: modelContext)
    }

    static func delete(_ person: Person, in modelContext: ModelContext) throws {
        let contactIdentifier = person.contactIdentifier
        try detachReferences(to: person, in: modelContext)
        try deleteModel(person, in: modelContext)

        if let contactIdentifier {
            ContactImportExclusionStore.exclude(contactIdentifier)
        }
    }

    private static func detachReferences(
        to place: Place,
        in modelContext: ModelContext
    ) throws {
        for details in try modelContext.fetch(FetchDescriptor<TransitDetails>()) {
            if details.originPlace?.id == place.id {
                details.originRawText = details.originRawText ?? place.name
                details.originPlace = nil
            }

            if details.destinationPlace?.id == place.id {
                details.destinationRawText = details.destinationRawText ?? place.name
                details.destinationPlace = nil
            }
        }

        for details in try modelContext.fetch(FetchDescriptor<PlaceVisitDetails>())
        where details.place?.id == place.id {
            details.placeRawText = details.placeRawText ?? place.name
            details.place = nil
        }

        let workoutDetails = try modelContext.fetch(
            FetchDescriptor<WorkoutDetails>()
        )
        for details in workoutDetails {
            if details.place?.id == place.id {
                details.place = nil
                details.placeResolutionSource = .automatic
                details.fieldReviews.removeAll { $0.field == .place }
                if details.sourceLocation == nil {
                    addWorkoutReview(.place, to: details)
                }
            }
            if details.originPlace?.id == place.id {
                details.originPlace = nil
                details.originResolutionSource = .automatic
                details.fieldReviews.removeAll { $0.field == .origin }
                if details.originLocation == nil {
                    addWorkoutReview(.origin, to: details)
                }
            }
            if details.destinationPlace?.id == place.id {
                details.destinationPlace = nil
                details.destinationResolutionSource = .automatic
                details.fieldReviews.removeAll { $0.field == .destination }
                if details.destinationLocation == nil {
                    addWorkoutReview(.destination, to: details)
                }
            }
        }

        for entry in try modelContext.fetch(FetchDescriptor<LogEntry>())
        where entry.kind == .workout {
            entry.needsReview = !(entry.workoutDetails?.fieldReviews.isEmpty ?? true)
        }

        for person in try modelContext.fetch(FetchDescriptor<Person>()) {
            if person.firstMetPlace?.id == place.id {
                person.firstMetPlace = nil
            }

            if person.lastMetPlace?.id == place.id {
                person.lastMetPlace = nil
            }
        }
    }

    private static func detachReferences(
        to person: Person,
        in modelContext: ModelContext
    ) throws {
        for entry in try modelContext.fetch(FetchDescriptor<LogEntry>()) {
            entry.people.removeAll { $0.id == person.id }
        }
    }

    private static func deleteModel<Model: PersistentModel>(
        _ model: Model,
        in modelContext: ModelContext
    ) throws {
        modelContext.delete(model)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func addWorkoutReview(
        _ field: WorkoutReviewField,
        to details: WorkoutDetails
    ) {
        details.fieldReviews.removeAll { $0.field == field }
        details.fieldReviews.append(
            WorkoutFieldReview(
                field: field,
                reason: String(localized: "The previously associated place was deleted.")
            )
        )
    }
}
