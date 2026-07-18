//
//  WorkoutPlaceReviewModel.swift
//  Journal
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class WorkoutPlaceReviewModel {
    var selectedPlaceID: UUID?
    var selectedOriginPlaceID: UUID?
    var selectedDestinationPlaceID: UUID?
    var errorMessage: String?

    init(entry: LogEntry) {
        selectedPlaceID = entry.workoutDetails?.place?.id
        selectedOriginPlaceID = entry.workoutDetails?.originPlace?.id
        selectedDestinationPlaceID = entry.workoutDetails?.destinationPlace?.id
    }

    subscript(placeIDFor field: WorkoutReviewField) -> UUID? {
        get {
            switch field {
            case .place: selectedPlaceID
            case .origin: selectedOriginPlaceID
            case .destination: selectedDestinationPlaceID
            }
        }
        set {
            switch field {
            case .place: selectedPlaceID = newValue
            case .origin: selectedOriginPlaceID = newValue
            case .destination: selectedDestinationPlaceID = newValue
            }
        }
    }

    func select(_ place: Place, for field: WorkoutReviewField) {
        self[placeIDFor: field] = place.id
    }

    func save(
        entry: LogEntry,
        places: [Place],
        in modelContext: ModelContext
    ) -> Bool {
        guard let details = entry.workoutDetails else { return false }

        if details.movementKind == .moving {
            apply(
                placeID: selectedOriginPlaceID,
                field: .origin,
                places: places,
                details: details
            )
            apply(
                placeID: selectedDestinationPlaceID,
                field: .destination,
                places: places,
                details: details
            )
        } else {
            apply(
                placeID: selectedPlaceID,
                field: .place,
                places: places,
                details: details
            )
        }

        entry.needsReview = !details.fieldReviews.isEmpty
        entry.weather = nil

        do {
            try modelContext.save()
            EntryWeatherService.refreshInBackground(entry, in: modelContext)
            return true
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func apply(
        placeID: UUID?,
        field: WorkoutReviewField,
        places: [Place],
        details: WorkoutDetails
    ) {
        guard let placeID else {
            clear(field: field, details: details)
            return
        }
        guard let place = places.first(where: { $0.id == placeID }) else {
            return
        }

        switch field {
        case .place:
            details.place = place
            details.placeResolutionSource = .manual
        case .origin:
            details.originPlace = place
            details.originResolutionSource = .manual
        case .destination:
            details.destinationPlace = place
            details.destinationResolutionSource = .manual
        }
        details.fieldReviews.removeAll { $0.field == field }
    }

    private func clear(
        field: WorkoutReviewField,
        details: WorkoutDetails
    ) {
        switch field {
        case .place:
            details.place = nil
            details.placeResolutionSource = .automatic
        case .origin:
            details.originPlace = nil
            details.originResolutionSource = .automatic
        case .destination:
            details.destinationPlace = nil
            details.destinationResolutionSource = .automatic
        }
        details.fieldReviews.removeAll { $0.field == field }
        guard location(for: field, in: details) == nil else { return }
        details.fieldReviews.append(
            WorkoutFieldReview(
                field: field,
                reason: String(localized: "HealthKit did not provide a location for this workout.")
            )
        )
    }

    private func location(
        for field: WorkoutReviewField,
        in details: WorkoutDetails
    ) -> Location? {
        switch field {
        case .place: details.sourceLocation
        case .origin: details.originLocation
        case .destination: details.destinationLocation
        }
    }
}
