import CoreLocation
import Foundation
import HealthKit
import SwiftData
import Testing

@testable import Journal

@Suite("HealthKit workouts")
@MainActor
struct WorkoutTests {
    @Test("Only walking and running are moving workouts")
    func movementClassification() {
        #expect(
            WorkoutActivityCatalog.movementKind(
                for: Int(HKWorkoutActivityType.walking.rawValue)
            ) == .moving
        )
        #expect(
            WorkoutActivityCatalog.movementKind(
                for: Int(HKWorkoutActivityType.running.rawValue)
            ) == .moving
        )
        #expect(
            WorkoutActivityCatalog.movementKind(
                for: Int(HKWorkoutActivityType.cycling.rawValue)
            ) == .staticWorkout
        )
        #expect(
            WorkoutActivityCatalog.movementKind(
                for: Int(HKWorkoutActivityType.yoga.rawValue)
            ) == .staticWorkout
        )
    }

    @Test("Metric extraction preserves HealthKit units and missing values")
    func metricExtraction() {
        let distance = HKQuantity(
            unit: .mile(),
            doubleValue: 1
        )
        let energy = HKQuantity(
            unit: .jouleUnit(with: .kilo),
            doubleValue: 418.4
        )

        #expect(
            abs(
                (HealthKitWorkoutClient.distanceMeters(from: distance) ?? 0)
                    - 1_609.344
            ) < 0.001
        )
        #expect(
            abs(
                (HealthKitWorkoutClient.activeEnergyKilocalories(
                    from: energy
                ) ?? 0) - 100
            ) < 0.001
        )
        #expect(HealthKitWorkoutClient.distanceMeters(from: nil) == nil)
        #expect(
            HealthKitWorkoutClient.activeEnergyKilocalories(from: nil) == nil
        )
    }

    @Test("Exact route points keep every point in timestamp order")
    func routePointOrdering() {
        let base = Date(timeIntervalSince1970: 10_000)
        let locations = [
            routeLocation(latitude: 3, timestamp: base.addingTimeInterval(3)),
            routeLocation(latitude: 1, timestamp: base.addingTimeInterval(1)),
            routeLocation(latitude: 2, timestamp: base.addingTimeInterval(2)),
            routeLocation(latitude: 2, timestamp: base.addingTimeInterval(2)),
            routeLocation(latitude: 100, timestamp: base),
        ]

        let ordered = HealthKitWorkoutClient.orderedRouteLocations(locations)

        #expect(ordered.count == locations.count - 1)
        #expect(ordered.map(\.coordinate.latitude) == [1, 2, 2, 3])
    }

    @Test("Matcher uses minimum, place, and HealthKit accuracy radii")
    func accuracyAwareMatching() throws {
        let minimumRadiusPlace = place(name: "Minimum", latitude: 0.00040)
        let minimumMatch = WorkoutPlaceMatcher.match(
            coordinate: coordinate(latitude: 0),
            places: [minimumRadiusPlace]
        )
        #expect(matchedPlace(minimumMatch)?.id == minimumRadiusPlace.id)

        let placeRadius = place(
            name: "Wide Place",
            latitude: 0.00075,
            accuracyRadiusMeters: 100
        )
        #expect(
            matchedPlace(
                WorkoutPlaceMatcher.match(
                    coordinate: coordinate(latitude: 0),
                    places: [placeRadius]
                )
            )?.id == placeRadius.id
        )

        let healthAccuracyPlace = place(
            name: "Health Accuracy",
            latitude: 0.00075
        )
        #expect(
            matchedPlace(
                WorkoutPlaceMatcher.match(
                    coordinate: coordinate(
                        latitude: 0,
                        horizontalAccuracyMeters: 100
                    ),
                    places: [healthAccuracyPlace]
                )
            )?.id == healthAccuracyPlace.id
        )

        let tooFar = place(name: "Too Far", latitude: 0.001)
        guard case .unmatched = WorkoutPlaceMatcher.match(
            coordinate: coordinate(latitude: 0),
            places: [tooFar]
        ) else {
            Issue.record("Expected a location outside every radius to be unmatched")
            return
        }
    }

    @Test("Matcher rejects similarly close saved places")
    func ambiguousAndClearNearestMatching() {
        let nearest = place(name: "Nearest", latitude: 0.00005)
        let ambiguousRunnerUp = place(
            name: "Ambiguous",
            latitude: 0.00020
        )
        guard case .ambiguous = WorkoutPlaceMatcher.match(
            coordinate: coordinate(latitude: 0),
            places: [nearest, ambiguousRunnerUp]
        ) else {
            Issue.record("Expected two similarly close places to remain unresolved")
            return
        }

        let clearRunnerUp = place(name: "Runner Up", latitude: 0.00040)
        #expect(
            matchedPlace(
                WorkoutPlaceMatcher.match(
                    coordinate: coordinate(latitude: 0),
                    places: [nearest, clearRunnerUp]
                )
            )?.id == nearest.id
        )
    }

    @Test("Workout upserts are idempotent and snapshot explicit times")
    func idempotentUpsert() throws {
        let context = try makeContext()
        let gym = place(
            name: "Gym",
            latitude: 45.65,
            timeZoneIdentifier: "Europe/Bucharest"
        )
        context.insert(gym)
        let uuid = UUID()
        let snapshot = staticSnapshot(
            uuid: uuid,
            routeStart: coordinate(latitude: 45.65, longitude: 0),
            distanceMeters: nil,
            activeEnergyKilocalories: 245
        )
        let resolved = WorkoutResolvedLocations(
            source: gym.location,
            origin: nil,
            destination: nil
        )

        let first = WorkoutEntryStore.upsert(
            snapshot: snapshot,
            locations: resolved,
            places: [gym],
            existingEntry: nil,
            in: context
        )
        let second = WorkoutEntryStore.upsert(
            snapshot: snapshot,
            locations: resolved,
            places: [gym],
            existingEntry: first,
            in: context
        )
        try context.save()

        #expect(first.id == second.id)
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).count == 1)
        #expect(second.kind == .workout)
        #expect(second.timeConfidence == .explicit)
        #expect(second.startTime == snapshot.startTime)
        #expect(second.endTime == snapshot.endTime)
        #expect(second.startTimeZoneIdentifier == "Europe/Bucharest")
        #expect(second.endTimeZoneIdentifier == "Europe/Bucharest")
        #expect(second.workoutDetails?.place?.id == gym.id)
        #expect(second.workoutDetails?.activeEnergyKilocalories == 245)
        #expect(second.needsReview == false)
    }

    @Test("Locationless static workouts require only place review")
    func locationlessStaticWorkout() throws {
        let context = try makeContext()
        let snapshot = staticSnapshot(
            uuid: UUID(),
            routeStart: nil,
            distanceMeters: nil,
            activeEnergyKilocalories: nil
        )
        let entry = WorkoutEntryStore.upsert(
            snapshot: snapshot,
            locations: WorkoutResolvedLocations(
                source: nil,
                origin: nil,
                destination: nil
            ),
            places: [],
            existingEntry: nil,
            in: context
        )

        #expect(entry.needsReview)
        #expect(entry.workoutDetails?.fieldReviews.map(\.field) == [.place])
        #expect(entry.workoutDetails?.distanceMeters == nil)
        #expect(entry.workoutDetails?.activeEnergyKilocalories == nil)
    }

    @Test("Unmatched workout coordinates use their address without review")
    func unmatchedCoordinateUsesAddress() throws {
        let context = try makeContext()
        let snapshot = staticSnapshot(
            uuid: UUID(),
            routeStart: coordinate(latitude: 45.65, longitude: 25.60),
            distanceMeters: nil,
            activeEnergyKilocalories: 180
        )
        let historicalLocation = Location(
            latitude: 45.65,
            longitude: 25.60,
            formattedAddress: "Strada Test, Brașov",
            timeZoneIdentifier: "Europe/Bucharest"
        )
        let entry = WorkoutEntryStore.upsert(
            snapshot: snapshot,
            locations: WorkoutResolvedLocations(
                source: historicalLocation,
                origin: nil,
                destination: nil
            ),
            places: [],
            existingEntry: nil,
            in: context
        )

        #expect(entry.needsReview == false)
        #expect(entry.workoutDetails?.place == nil)
        #expect(entry.workoutDetails?.fieldReviews.isEmpty == true)
        #expect(
            TimelineEntrySnapshot(entry: entry).workoutPlace
                == "Strada Test, Brașov"
        )
    }

    @Test("Workout locations prefer a compact place and city label")
    func compactWorkoutLocationLabel() {
        let location = Location(
            latitude: 44.4396,
            longitude: 26.0963,
            formattedAddress:
                "Piața Revoluției, Bucharest, 010038, Romania",
            compactAddress: "Piața Revoluției, Bucharest"
        )
        let legacyLocation = Location(
            latitude: 44.4396,
            longitude: 26.0963,
            formattedAddress:
                "Piața Revoluției, Bucharest, 010038, Romania"
        )

        #expect(
            WorkoutLocationPresentation.name(
                place: nil,
                location: location
            ) == "Piața Revoluției, Bucharest"
        )
        #expect(
            WorkoutLocationPresentation.name(
                place: nil,
                location: legacyLocation
            ) == "Piața Revoluției, Bucharest"
        )
    }

    @Test("Automatic reimport preserves manually reviewed associations")
    func preservesManualPlaces() throws {
        let context = try makeContext()
        let chosen = place(name: "Chosen", latitude: 10)
        context.insert(chosen)
        let original = movingSnapshot(
            uuid: UUID(),
            routeStart: coordinate(latitude: 0),
            routeEnd: coordinate(latitude: 0.01)
        )
        let entry = WorkoutEntryStore.upsert(
            snapshot: original,
            locations: WorkoutResolvedLocations(
                source: nil,
                origin: location(latitude: 0),
                destination: location(latitude: 0.01)
            ),
            places: [],
            existingEntry: nil,
            in: context
        )
        entry.workoutDetails?.originPlace = chosen
        entry.workoutDetails?.originResolutionSource = .manual
        entry.workoutDetails?.fieldReviews.removeAll { $0.field == .origin }

        let changed = movingSnapshot(
            uuid: original.uuid,
            routeStart: coordinate(latitude: 20),
            routeEnd: coordinate(latitude: 21)
        )
        _ = WorkoutEntryStore.upsert(
            snapshot: changed,
            locations: WorkoutResolvedLocations(
                source: nil,
                origin: location(latitude: 20),
                destination: location(latitude: 21)
            ),
            places: [],
            existingEntry: entry,
            in: context
        )

        #expect(entry.workoutDetails?.originPlace?.id == chosen.id)
        #expect(
            entry.workoutDetails?.originResolutionSource == .manual
        )
    }

    @Test("Moving workouts use transit-style cross-zone projection")
    func movingWorkoutTimelineProjection() throws {
        let start = try Date("2026-07-17T22:00:00+03:00", strategy: .iso8601)
        let end = try Date("2026-07-18T01:00:00-04:00", strategy: .iso8601)
        let snapshot = TimelineEntrySnapshot(
            createdAt: start,
            startTime: start,
            endTime: end,
            startTimeZoneIdentifier: "Europe/Bucharest",
            endTimeZoneIdentifier: "America/New_York",
            creationTimeZoneIdentifier: "Europe/Bucharest",
            timeConfidence: .explicit,
            kind: .workout,
            workoutActivityName: "Running",
            workoutMovementKind: .moving
        )

        let arrivalDay = TimelineProjection.project(
            entries: [snapshot],
            for: TimelineDayKey(year: 2026, month: 7, day: 18)
        )

        #expect(arrivalDay.occurrences.map(\.role) == [.intervalDay])
        #expect(arrivalDay.occurrences.first?.changesTimeZone == true)
    }

    @Test("Workout weather uses the historical start location")
    func workoutWeatherLocation() throws {
        let start = Date(timeIntervalSince1970: 50_000)
        let entry = LogEntry(
            kind: .workout,
            startTime: start,
            needsReview: false
        )
        entry.workoutDetails = WorkoutDetails(
            healthKitWorkoutUUID: UUID(),
            activityTypeRawValue: WorkoutActivityCatalog.walkingRawValue,
            activityName: "Walking",
            movementKind: .moving,
            originLocation: location(latitude: 44.4, longitude: 26.1),
            destinationLocation: location(latitude: 44.5, longitude: 26.2)
        )

        let request = try #require(EntryWeatherService.request(for: entry))
        #expect(request.date == start)
        #expect(request.latitude == 44.4)
        #expect(request.longitude == 26.1)
    }

    @Test("Selected-day model context includes workouts but forbids generating them")
    func workoutLLMHistory() {
        let home = place(name: "Home", latitude: 45.65)
        let entry = LogEntry(
            kind: .workout,
            startTime: Date(timeIntervalSince1970: 100_000),
            endTime: Date(timeIntervalSince1970: 103_600),
            startTimeZoneIdentifier: "Europe/Bucharest",
            endTimeZoneIdentifier: "Europe/Bucharest",
            creationTimeZoneIdentifier: "Europe/Bucharest",
            timeConfidence: .explicit,
            needsReview: false
        )
        entry.workoutDetails = WorkoutDetails(
            healthKitWorkoutUUID: UUID(),
            activityTypeRawValue: WorkoutActivityCatalog.walkingRawValue,
            activityName: "Walking",
            movementKind: .moving,
            distanceMeters: 3_200,
            originPlace: home,
            destinationPlace: home
        )
        let references = EntryPromptReferences(places: [home], people: [])
        let prompt = EntryLanguageModelService.prompt(
            input: "walk home from there",
            context: EntryPromptContext(
                places: [home],
                people: [],
                transitTypes: [],
                visitStatisticsByPlaceID: [:],
                selectedDay: TimelineDayKey(
                    year: 2026,
                    month: 7,
                    day: 18
                ),
                selectedDayEntries: [entry],
                currentDate: Date(timeIntervalSince1970: 104_000),
                currentLocation: home.location
            ),
            references: references
        )

        #expect(prompt.contains(#""entryKind" : "workout""#))
        #expect(prompt.contains(#""activityName" : "Walking""#))
        #expect(prompt.contains(#""distanceKilometers" : 3.2"#))
        #expect(
            EntryLanguageModelService.instructions.contains(
                "workout is never an output entryKind"
            )
        )
    }

    @Test("Locally deleted workouts receive an exclusion tombstone")
    func localDeletionTombstone() throws {
        let context = try makeContext()
        let uuid = UUID()
        let entry = LogEntry(kind: .workout, needsReview: false)
        entry.workoutDetails = WorkoutDetails(
            healthKitWorkoutUUID: uuid,
            activityTypeRawValue: WorkoutActivityCatalog.walkingRawValue,
            activityName: "Walking",
            movementKind: .moving
        )
        context.insert(entry)
        try context.save()

        try JournalDeletionService.delete(entry, in: context)
        defer { WorkoutImportPreferences.removeExclusion(uuid) }

        #expect(WorkoutImportPreferences.isExcluded(uuid))
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).isEmpty)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            LogEntry.self,
            Person.self,
            Place.self,
            TransitDetails.self,
            PlaceVisitDetails.self,
            WorkoutDetails.self,
            TransitType.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func place(
        name: String,
        latitude: Double,
        longitude: Double = 0,
        accuracyRadiusMeters: Double = 0,
        timeZoneIdentifier: String? = nil
    ) -> Place {
        Place(
            name: name,
            location: location(
                latitude: latitude,
                longitude: longitude,
                timeZoneIdentifier: timeZoneIdentifier
            ),
            accuracyRadiusMeters: accuracyRadiusMeters
        )
    }

    private func location(
        latitude: Double,
        longitude: Double = 0,
        timeZoneIdentifier: String? = nil
    ) -> Location {
        Location(
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    private func coordinate(
        latitude: Double,
        longitude: Double = 0,
        horizontalAccuracyMeters: Double = 5
    ) -> WorkoutCoordinateSnapshot {
        WorkoutCoordinateSnapshot(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracyMeters: horizontalAccuracyMeters
        )
    }

    private func staticSnapshot(
        uuid: UUID,
        routeStart: WorkoutCoordinateSnapshot?,
        distanceMeters: Double?,
        activeEnergyKilocalories: Double?
    ) -> HealthKitWorkoutSnapshot {
        HealthKitWorkoutSnapshot(
            uuid: uuid,
            activityTypeRawValue: Int(HKWorkoutActivityType.yoga.rawValue),
            activityName: "Yoga",
            movementKind: .staticWorkout,
            startTime: Date(timeIntervalSince1970: 10_000),
            endTime: Date(timeIntervalSince1970: 13_600),
            metadataTimeZoneIdentifier: nil,
            distanceMeters: distanceMeters,
            activeEnergyKilocalories: activeEnergyKilocalories,
            routeState: routeStart == nil ? .unavailable : .available,
            routeStart: routeStart,
            routeEnd: routeStart
        )
    }

    private func movingSnapshot(
        uuid: UUID,
        routeStart: WorkoutCoordinateSnapshot,
        routeEnd: WorkoutCoordinateSnapshot
    ) -> HealthKitWorkoutSnapshot {
        HealthKitWorkoutSnapshot(
            uuid: uuid,
            activityTypeRawValue: WorkoutActivityCatalog.walkingRawValue,
            activityName: "Walking",
            movementKind: .moving,
            startTime: Date(timeIntervalSince1970: 20_000),
            endTime: Date(timeIntervalSince1970: 21_800),
            metadataTimeZoneIdentifier: nil,
            distanceMeters: 1_500,
            activeEnergyKilocalories: 100,
            routeState: .available,
            routeStart: routeStart,
            routeEnd: routeEnd
        )
    }

    private func matchedPlace(
        _ result: WorkoutPlaceMatchResult
    ) -> Place? {
        guard case .matched(let place) = result else { return nil }
        return place
    }

    private func routeLocation(
        latitude: Double,
        timestamp: Date
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: latitude,
                longitude: 0
            ),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: timestamp
        )
    }
}
