//
//  HealthKitWorkoutClient.swift
//  Journal
//

import CoreLocation
import Foundation
import HealthKit

enum HealthKitWorkoutClientError: LocalizedError {
    case healthDataUnavailable
    case workoutUnavailable

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            String(localized: "Health data is unavailable on this device.")
        case .workoutUnavailable:
            String(localized: "This workout is no longer available in Health.")
        }
    }
}

struct HealthKitWorkoutSnapshot: Sendable {
    let uuid: UUID
    let activityTypeRawValue: Int
    let activityName: String
    let movementKind: WorkoutMovementKind
    let startTime: Date
    let endTime: Date
    let metadataTimeZoneIdentifier: String?
    let distanceMeters: Double?
    let activeEnergyKilocalories: Double?
    let routeState: WorkoutRouteImportState
    let routeStart: WorkoutCoordinateSnapshot?
    let routeEnd: WorkoutCoordinateSnapshot?
}

struct HealthKitWorkoutChangeSet: Sendable {
    let workouts: [HealthKitWorkoutSnapshot]
    let deletedWorkoutUUIDs: [UUID]
    let newAnchor: HKQueryAnchor
}

actor HealthKitWorkoutClient {
    static let shared = HealthKitWorkoutClient()

    private let healthStore = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitWorkoutClientError.healthDataUnavailable
        }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
        ]
        try await healthStore.requestAuthorization(
            toShare: [],
            read: readTypes
        )
    }

    func changes(
        since anchor: HKQueryAnchor?,
        cutoff: Date
    ) async throws -> HealthKitWorkoutChangeSet {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitWorkoutClientError.healthDataUnavailable
        }

        let datePredicate = HKQuery.predicateForSamples(
            withStart: cutoff,
            end: nil,
            options: [.strictStartDate]
        )
        let descriptor = HKAnchoredObjectQueryDescriptor<HKWorkout>(
            predicates: [.workout(datePredicate)],
            anchor: anchor
        )
        let result = try await descriptor.result(for: healthStore)
        var snapshots: [HealthKitWorkoutSnapshot] = []
        snapshots.reserveCapacity(result.addedSamples.count)

        for workout in result.addedSamples {
            snapshots.append(await snapshot(for: workout))
        }

        return HealthKitWorkoutChangeSet(
            workouts: snapshots,
            deletedWorkoutUUIDs: result.deletedObjects.map(\.uuid),
            newAnchor: result.newAnchor
        )
    }

    func exactRoute(for workoutUUID: UUID) async throws -> [WorkoutCoordinateSnapshot] {
        guard let workout = try await workout(with: workoutUUID) else {
            throw HealthKitWorkoutClientError.workoutUnavailable
        }
        return try await routeLocations(for: workout).map(WorkoutCoordinateSnapshot.init)
    }

    func currentSnapshot(for workoutUUID: UUID) async throws -> HealthKitWorkoutSnapshot {
        guard let workout = try await workout(with: workoutUUID) else {
            throw HealthKitWorkoutClientError.workoutUnavailable
        }
        return await snapshot(for: workout)
    }

    func startObservingChanges(
        cutoff: Date,
        onChange: @escaping @MainActor @Sendable () async -> Void
    ) {
        guard observerQueries.isEmpty, HKHealthStore.isHealthDataAvailable() else {
            return
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: cutoff,
            end: nil,
            options: [.strictStartDate]
        )
        let sampleTypes: [HKSampleType] = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
        observerQueries = sampleTypes.map { sampleType in
            HKObserverQuery(sampleType: sampleType, predicate: predicate) {
                _, completion, error in
                guard error == nil else {
                    completion()
                    return
                }

                Task { @MainActor in
                    await onChange()
                    completion()
                }
            }
        }
        for query in observerQueries {
            healthStore.execute(query)
        }
    }

    private func snapshot(for workout: HKWorkout) async -> HealthKitWorkoutSnapshot {
        let rawValue = Int(workout.workoutActivityType.rawValue)
        let presentation = WorkoutActivityCatalog.presentation(for: rawValue)
        let movementKind = WorkoutActivityCatalog.movementKind(for: rawValue)
        let route: [CLLocation]
        let routeState: WorkoutRouteImportState

        do {
            route = try await routeLocations(for: workout)
            routeState = route.isEmpty ? .unavailable : .available
        } catch {
            route = []
            routeState = .pending
        }

        return HealthKitWorkoutSnapshot(
            uuid: workout.uuid,
            activityTypeRawValue: rawValue,
            activityName: presentation.name,
            movementKind: movementKind,
            startTime: workout.startDate,
            endTime: workout.endDate,
            metadataTimeZoneIdentifier:
                Self.metadataTimeZoneIdentifier(for: workout),
            distanceMeters: movementKind == .moving
                ? Self.distanceMeters(for: workout)
                : nil,
            activeEnergyKilocalories: Self.activeEnergyKilocalories(
                for: workout
            ),
            routeState: routeState,
            routeStart: route.first.map(WorkoutCoordinateSnapshot.init),
            routeEnd: route.last.map(WorkoutCoordinateSnapshot.init)
        )
    }

    private func workout(with uuid: UUID) async throws -> HKWorkout? {
        let predicate = HKQuery.predicateForObject(with: uuid)
        let descriptor = HKSampleQueryDescriptor<HKWorkout>(
            predicates: [.workout(predicate)],
            sortDescriptors: [],
            limit: 1
        )
        return try await descriptor.result(for: healthStore).first
    }

    private func routeLocations(for workout: HKWorkout) async throws -> [CLLocation] {
        let predicate = HKQuery.predicateForObjects(from: workout)
        let descriptor = HKSampleQueryDescriptor<HKWorkoutRoute>(
            predicates: [.workoutRoute(predicate)],
            sortDescriptors: [SortDescriptor(\HKWorkoutRoute.startDate)]
        )
        let routes = try await descriptor.result(for: healthStore)
        var locations: [CLLocation] = []

        for route in routes {
            let routeDescriptor = HKWorkoutRouteQueryDescriptor(route)
            for try await location in routeDescriptor.results(for: healthStore) {
                locations.append(location)
            }
        }

        return Self.orderedRouteLocations(locations)
    }

    nonisolated static func orderedRouteLocations(
        _ locations: [CLLocation]
    ) -> [CLLocation] {
        locations.filter {
            CLLocationCoordinate2DIsValid($0.coordinate)
                && $0.coordinate.latitude.isFinite
                && $0.coordinate.longitude.isFinite
        }.sorted { $0.timestamp < $1.timestamp }
    }

    nonisolated static func distanceMeters(
        for workout: HKWorkout
    ) -> Double? {
        let type = HKQuantityType(.distanceWalkingRunning)
        return distanceMeters(
            from: workout.statistics(for: type)?.sumQuantity()
        )
    }

    nonisolated static func activeEnergyKilocalories(
        for workout: HKWorkout
    ) -> Double? {
        let type = HKQuantityType(.activeEnergyBurned)
        return activeEnergyKilocalories(
            from: workout.statistics(for: type)?.sumQuantity()
        )
    }

    nonisolated static func distanceMeters(
        from quantity: HKQuantity?
    ) -> Double? {
        quantity?.doubleValue(for: .meter())
    }

    nonisolated static func activeEnergyKilocalories(
        from quantity: HKQuantity?
    ) -> Double? {
        quantity?.doubleValue(for: .kilocalorie())
    }

    nonisolated static func metadataTimeZoneIdentifier(
        for workout: HKWorkout
    ) -> String? {
        let value = workout.metadata?[HKMetadataKeyTimeZone]
        if let timeZone = value as? TimeZone {
            return timeZone.identifier
        }
        return value as? String
    }
}
