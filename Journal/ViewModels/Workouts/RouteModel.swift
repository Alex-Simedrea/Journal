//
//  WorkoutRouteModel.swift
//  Journal
//

import Foundation
import HealthKit
import Observation

enum WorkoutRouteLoadState: Equatable {
    case idle
    case loading
    case loaded
    case authorizationRequired
    case unavailable
    case failed(String)
}

@MainActor
@Observable
final class WorkoutRouteModel {
    private(set) var state: WorkoutRouteLoadState = .idle
    private(set) var points: [WorkoutCoordinateSnapshot] = []

    @ObservationIgnored
    private let client: HealthKitWorkoutClient

    init(client: HealthKitWorkoutClient = .shared) {
        self.client = client
    }

    func load(workoutUUID: UUID) async {
        state = .loading
        do {
            let loadedPoints = try await client.exactRoute(
                for: workoutUUID
            )
            points = loadedPoints
            state = loadedPoints.isEmpty ? .unavailable : .loaded
        } catch is CancellationError {
            return
        } catch {
            points = []
            state = Self.authorizationIsRequired(for: error)
                ? .authorizationRequired
                : .failed(error.localizedDescription)
        }
    }

    private static func authorizationIsRequired(for error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == HKErrorDomain else { return false }
        return [
            HKError.Code.errorAuthorizationDenied.rawValue,
            HKError.Code.errorAuthorizationNotDetermined.rawValue,
            HKError.Code.errorRequiredAuthorizationDenied.rawValue,
        ].contains(error.code)
    }
}
