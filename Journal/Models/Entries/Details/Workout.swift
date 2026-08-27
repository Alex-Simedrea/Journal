//
//  WorkoutDetails.swift
//  Journal
//

import Foundation
import SwiftData

nonisolated enum WorkoutMovementKind: String, Codable, Hashable, Sendable {
    case moving
    case staticWorkout
}

nonisolated enum WorkoutRouteImportState: String, Codable, Hashable, Sendable {
    case pending
    case available
    case unavailable
}

nonisolated enum WorkoutPlaceResolutionSource: String, Codable, Hashable, Sendable {
    case automatic
    case manual
}

nonisolated enum WorkoutReviewField: String, Codable, CaseIterable, Hashable, Sendable {
    case place
    case origin
    case destination
}

nonisolated struct WorkoutFieldReview: Codable, Hashable, Identifiable, Sendable {
    var field: WorkoutReviewField
    var reason: String

    var id: WorkoutReviewField { field }
}

@Model
final class WorkoutDetails {
    @Attribute(.unique) var healthKitWorkoutUUID: UUID
    var activityTypeRawValue: Int
    var activityName: String
    var movementKind: WorkoutMovementKind
    var distanceMeters: Double?
    var activeEnergyKilocalories: Double?
    var routeImportState: WorkoutRouteImportState

    var sourceLocation: Location?
    var originLocation: Location?
    var destinationLocation: Location?

    var place: Place?
    var originPlace: Place?
    var destinationPlace: Place?

    var placeResolutionSource: WorkoutPlaceResolutionSource
    var originResolutionSource: WorkoutPlaceResolutionSource
    var destinationResolutionSource: WorkoutPlaceResolutionSource
    /// SwiftData's automatic handling for arrays of Codable values can
    /// intermittently attempt to materialize the stored JSON blob as a native
    /// collection and trap before decoding it. Keep the same persisted column,
    /// but own the JSON coding so an empty `[]` remains an ordinary Data value.
    @Attribute(originalName: "fieldReviews")
    private var fieldReviewsData: Data?

    var fieldReviews: [WorkoutFieldReview] {
        get {
            PersistedJSON.decode(
                [WorkoutFieldReview].self,
                from: fieldReviewsData
            ) ?? []
        }
        set { fieldReviewsData = PersistedJSON.encode(newValue) }
    }

    init(
        healthKitWorkoutUUID: UUID,
        activityTypeRawValue: Int,
        activityName: String,
        movementKind: WorkoutMovementKind,
        distanceMeters: Double? = nil,
        activeEnergyKilocalories: Double? = nil,
        routeImportState: WorkoutRouteImportState = .pending,
        sourceLocation: Location? = nil,
        originLocation: Location? = nil,
        destinationLocation: Location? = nil,
        place: Place? = nil,
        originPlace: Place? = nil,
        destinationPlace: Place? = nil,
        placeResolutionSource: WorkoutPlaceResolutionSource = .automatic,
        originResolutionSource: WorkoutPlaceResolutionSource = .automatic,
        destinationResolutionSource: WorkoutPlaceResolutionSource = .automatic,
        fieldReviews: [WorkoutFieldReview] = []
    ) {
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.activityTypeRawValue = activityTypeRawValue
        self.activityName = activityName
        self.movementKind = movementKind
        self.distanceMeters = distanceMeters
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.routeImportState = routeImportState
        self.sourceLocation = sourceLocation
        self.originLocation = originLocation
        self.destinationLocation = destinationLocation
        self.place = place
        self.originPlace = originPlace
        self.destinationPlace = destinationPlace
        self.placeResolutionSource = placeResolutionSource
        self.originResolutionSource = originResolutionSource
        self.destinationResolutionSource = destinationResolutionSource
        self.fieldReviewsData = PersistedJSON.encode(fieldReviews)
    }

    func review(for field: WorkoutReviewField) -> WorkoutFieldReview? {
        fieldReviews.first { $0.field == field }
    }
}
