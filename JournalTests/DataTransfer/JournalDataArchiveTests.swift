import Foundation
import SwiftData
import Testing

@testable import Journal

@Suite("Journal data archive")
@MainActor
struct JournalDataArchiveTests {
    @Test("Export and import preserve data and relationships")
    func roundTrip() throws {
        let context = try makeContext()
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000.123)
        let origin = Location(
            latitude: 44.4268,
            longitude: 26.1025,
            displayName: "Home",
            systemImage: .house,
            formattedAddress: "1 Origin Street, Bucharest, Romania",
            compactAddress: "1 Origin Street, Bucharest",
            timeZoneIdentifier: "Europe/Bucharest",
            cityName: "Bucharest",
            countryName: "Romania",
            countryCode: "RO"
        )
        let destination = Location(
            latitude: 48.8566,
            longitude: 2.3522,
            displayName: "Destination",
            systemImage: .cafe,
            formattedAddress: "2 Destination Street, Paris, France",
            compactAddress: "2 Destination Street, Paris",
            timeZoneIdentifier: "Europe/Paris",
            cityName: "Paris",
            countryName: "France",
            countryCode: "FR"
        )
        let home = Place(
            id: UUID(),
            name: "Home",
            aliases: ["My place"],
            location: origin,
            systemImage: .house,
            createdAt: baseDate,
            accuracyRadiusMeters: 75
        )
        let cafe = Place(
            id: UUID(),
            name: "Cafe",
            aliases: ["Coffee"],
            location: destination,
            systemImage: .cafe,
            createdAt: baseDate.addingTimeInterval(1),
            accuracyRadiusMeters: 30
        )
        let person = Person(
            id: UUID(),
            name: "Alex",
            aliases: ["A"],
            contactIdentifier: "contact-1",
            firstMetAt: baseDate,
            firstMetPlace: home,
            lastMetAt: baseDate.addingTimeInterval(600),
            lastMetPlace: cafe
        )
        let type = TransitType(
            canonicalName: "Train",
            aliases: ["Rail"],
            routingMode: .automobile
        )
        let transitID = UUID()
        let candidateID = UUID()
        let recordingID = UUID()
        let transit = LogEntry(
            id: transitID,
            kind: .transit,
            createdAt: baseDate,
            startTime: baseDate.addingTimeInterval(60),
            endTime: baseDate.addingTimeInterval(3_660),
            startTimeZoneIdentifier: "Europe/Bucharest",
            endTimeZoneIdentifier: "Europe/Paris",
            creationTimeZoneIdentifier: "Asia/Tokyo",
            timeConfidence: .manualOverride,
            rawInputString: "raw",
            automationCandidateID: candidateID,
            journalRecordingID: recordingID,
            photoReferences: [
                PhotoReference(
                    assetLocalIdentifier: "photo-1",
                    addedAt: baseDate
                )
            ],
            weather: EntryWeather(
                condition: "Clear",
                symbolName: "sun.max",
                temperatureCelsius: 20,
                humidity: 0.4,
                date: baseDate
            ),
            endWeather: EntryWeather(
                condition: "Rain",
                symbolName: "cloud.rain",
                temperatureCelsius: 14,
                humidity: 0.8,
                date: baseDate.addingTimeInterval(3_600)
            ),
            dayWeatherRecords: [
                PersistedDayWeather(
                    year: 2027,
                    month: 1,
                    day: 15,
                    latitude: origin.latitude,
                    longitude: origin.longitude,
                    timeZoneIdentifier: "Europe/Bucharest",
                    weather: EntryWeather(
                        condition: "Cloudy",
                        symbolName: "cloud",
                        temperatureCelsius: 16,
                        humidity: 0.6,
                        date: baseDate
                    ),
                    isFinal: true
                )
            ],
            wakeUpSourceSampleUUID: UUID(),
            sleepDurationSeconds: 28_800,
            entryKindReviewReason: "Review source",
            needsReview: true
        )
        transit.people = [person]
        transit.transitDetails = TransitDetails(
            type: "Train",
            sourceOrganizationName: "Railway",
            sourceServiceIdentifier: "ICE 42",
            originPlace: home,
            originLocation: origin,
            originRawText: "origin raw",
            destinationPlace: cafe,
            destinationLocation: destination,
            destinationRawText: "destination raw",
            durationSource: .manualOverride,
            distanceMeters: 1_000,
            recordedRoute: [
                RecordedRoutePoint(
                    latitude: origin.latitude,
                    longitude: origin.longitude,
                    timestamp: baseDate.addingTimeInterval(60)
                ),
                RecordedRoutePoint(
                    latitude: destination.latitude,
                    longitude: destination.longitude,
                    timestamp: baseDate.addingTimeInterval(3_660)
                ),
            ],
            recordedMotion: [
                RecordedMotionObservation(
                    startTime: baseDate.addingTimeInterval(60),
                    endTime: baseDate.addingTimeInterval(3_660),
                    kind: .automotive,
                    confidenceRawValue: 2
                )
            ],
            recordedTransitMode: .automotive,
            originCandidates: [candidate(at: origin, name: "Origin")],
            destinationCandidates: [
                candidate(at: destination, name: "Destination")
            ],
            unresolvedPeople: ["Sam"],
            fieldReviews: [
                TransitFieldReview(field: .destination, reason: "Check")
            ]
        )

        let visit = LogEntry(
            kind: .placeVisit,
            startTime: baseDate.addingTimeInterval(7_200),
            endTime: baseDate.addingTimeInterval(8_200),
            needsReview: false
        )
        visit.placeVisitDetails = PlaceVisitDetails(
            description: "Coffee",
            place: cafe,
            location: destination,
            placeRawText: "Cafe raw",
            candidates: [candidate(at: destination, name: "Cafe")],
            unresolvedPeople: ["Taylor"],
            fieldReviews: [
                PlaceVisitFieldReview(field: .place, reason: "Check")
            ]
        )

        let workoutUUID = UUID()
        let workout = LogEntry(
            kind: .workout,
            startTime: baseDate.addingTimeInterval(9_000),
            endTime: baseDate.addingTimeInterval(10_000),
            needsReview: false
        )
        workout.workoutDetails = WorkoutDetails(
            healthKitWorkoutUUID: workoutUUID,
            activityTypeRawValue: 37,
            activityName: "Cycling",
            movementKind: .moving,
            distanceMeters: 12_345,
            activeEnergyKilocalories: 456,
            routeImportState: .available,
            sourceLocation: origin,
            originLocation: origin,
            destinationLocation: destination,
            place: home,
            originPlace: home,
            destinationPlace: cafe,
            placeResolutionSource: .manual,
            originResolutionSource: .automatic,
            destinationResolutionSource: .manual,
            fieldReviews: [
                WorkoutFieldReview(field: .destination, reason: "Review")
            ]
        )

        let candidate = AutomationCandidate(
            id: candidateID,
            sourceFingerprint: "motion:test",
            kind: .transit,
            status: .pending,
            createdAt: baseDate,
            updatedAt: baseDate.addingTimeInterval(2),
            startTime: baseDate.addingTimeInterval(60),
            endTime: baseDate.addingTimeInterval(3_660),
            timeZoneIdentifier: "Europe/Bucharest",
            visitLocation: destination,
            visitHorizontalAccuracyMeters: 20,
            visitPlaceID: cafe.id,
            motionKind: .automotive,
            motionConfidenceRawValue: 2,
            originLocation: origin,
            originPlaceID: home.id,
            destinationLocation: destination,
            destinationPlaceID: cafe.id,
            acceptedEntryID: transitID,
            provenanceRecordedAt: baseDate.addingTimeInterval(4)
        )

        for model in [home, cafe] { context.insert(model) }
        context.insert(person)
        context.insert(type)
        for entry in [transit, visit, workout] { context.insert(entry) }
        context.insert(candidate)
        context.insert(
            TransitDetails(
                type: "Orphan",
                originRawText: "Preserve standalone model rows"
            )
        )
        try context.save()

        let data = try JournalDataArchiveService.exportData(from: context)
        let archive = try JournalDataArchiveService.decode(data)
        #expect(archive.places.count == 2)
        #expect(archive.people.count == 1)
        #expect(archive.transitTypes.count == 1)
        #expect(archive.entries.count == 3)
        #expect(archive.automationCandidates.count == 1)
        #expect(archive.orphanTransitDetails.count == 1)

        context.insert(Place(name: "Sentinel", location: origin))
        try context.save()
        try JournalDataArchiveService.replaceAllData(
            with: archive,
            in: context
        )

        let importedPlaces = try context.fetch(FetchDescriptor<Place>())
        let importedPeople = try context.fetch(FetchDescriptor<Person>())
        let importedEntries = try context.fetch(FetchDescriptor<LogEntry>())
        let importedCandidates = try context.fetch(
            FetchDescriptor<AutomationCandidate>()
        )
        let importedTransitDetails = try context.fetch(
            FetchDescriptor<TransitDetails>()
        )
        #expect(importedPlaces.count == 2)
        #expect(!importedPlaces.contains { $0.name == "Sentinel" })
        let importedPerson = try #require(importedPeople.first)
        #expect(importedPerson.firstMetPlace?.id == home.id)
        #expect(importedPerson.lastMetPlace?.id == cafe.id)

        let importedTransit = try #require(
            importedEntries.first { $0.id == transitID }
        )
        #expect(importedTransit.people.map(\.id) == [person.id])
        #expect(importedTransit.journalRecordingID == recordingID)
        #expect(importedTransit.startTimeZoneIdentifier == "Europe/Bucharest")
        #expect(importedTransit.endTimeZoneIdentifier == "Europe/Paris")
        #expect(importedTransit.photoReferences.first?.assetLocalIdentifier == "photo-1")
        #expect(importedTransit.weather?.condition == "Clear")
        #expect(importedTransit.endWeather?.condition == "Rain")
        #expect(importedTransit.dayWeatherRecords.first?.isFinal == true)
        #expect(importedTransit.transitDetails?.originPlace?.id == home.id)
        #expect(importedTransit.transitDetails?.destinationPlace?.id == cafe.id)
        #expect(importedTransit.transitDetails?.destinationRawText == "destination raw")
        #expect(importedTransit.transitDetails?.recordedRoute.count == 2)
        #expect(importedTransit.transitDetails?.recordedMotion.first?.kind == .automotive)
        #expect(importedTransit.transitDetails?.recordedTransitMode == .automotive)

        let importedWorkout = try #require(
            importedEntries.first { $0.kind == .workout }
        )
        #expect(importedWorkout.workoutDetails?.healthKitWorkoutUUID == workoutUUID)
        #expect(importedWorkout.workoutDetails?.destinationPlace?.id == cafe.id)
        let importedCandidate = try #require(importedCandidates.first)
        #expect(importedCandidate.id == candidateID)
        #expect(importedCandidate.originPlaceID == home.id)
        #expect(importedCandidate.destinationPlaceID == cafe.id)
        #expect(importedTransitDetails.count == 2)
        #expect(importedTransitDetails.contains { $0.type == "Orphan" })

        let reexported = try JournalDataArchiveService.decode(
            JournalDataArchiveService.exportData(from: context)
        )
        #expect(reexported.entries.count == archive.entries.count)
        #expect(reexported.entries.map(\.id) == archive.entries.map(\.id))
    }

    @Test("Unsupported backups do not modify current data")
    func unsupportedVersionDoesNotOverwrite() throws {
        let context = try makeContext()
        let place = Place(
            name: "Keep Me",
            location: Location(latitude: 1, longitude: 2)
        )
        context.insert(place)
        try context.save()

        let goodData = try JournalDataArchiveService.exportData(from: context)
        var object = try #require(
            JSONSerialization.jsonObject(with: goodData) as? [String: Any]
        )
        object["formatVersion"] = 999
        let invalidData = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: JournalDataArchiveError.self) {
            _ = try JournalDataArchiveService.decode(invalidData)
        }
        #expect(try context.fetch(FetchDescriptor<Place>()).first?.id == place.id)
    }

    @Test("An on-disk restore does not upsert embedded weather values")
    func onDiskWeatherRestore() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "JournalDataArchiveTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let context = try makeContext(
            storeURL: directory.appending(path: "Journal.store")
        )
        let entryID = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = LogEntry(
            id: entryID,
            kind: .placeVisit,
            createdAt: date,
            startTime: date,
            endTime: date.addingTimeInterval(600),
            weather: EntryWeather(
                condition: "Clear",
                symbolName: "sun.max",
                temperatureCelsius: 22,
                humidity: 0.5,
                date: date
            ),
            endWeather: EntryWeather(
                condition: "Cloudy",
                symbolName: "cloud",
                temperatureCelsius: 19,
                humidity: 0.6,
                date: date.addingTimeInterval(600)
            ),
            needsReview: false
        )
        entry.placeVisitDetails = PlaceVisitDetails(
            description: "Weather restore"
        )
        context.insert(entry)
        try context.save()

        let archive = try JournalDataArchiveService.decode(
            JournalDataArchiveService.exportData(from: context)
        )
        try JournalDataArchiveService.replaceAllData(
            with: archive,
            in: context
        )

        let restored = try #require(
            context.fetch(FetchDescriptor<LogEntry>()).first
        )
        #expect(restored.id == entryID)
        #expect(restored.weather?.condition == "Clear")
        #expect(restored.endWeather?.condition == "Cloudy")
    }

    private func candidate(
        at location: Location,
        name: String
    ) -> LocationCandidate {
        LocationCandidate(
            name: name,
            address: location.formattedAddress,
            latitude: location.latitude,
            longitude: location.longitude,
            timeZoneIdentifier: location.timeZoneIdentifier,
            cityName: location.cityName,
            countryName: location.countryName,
            countryCode: location.countryCode,
            distanceKilometers: 1,
            walkingDurationMinutes: 10,
            automobileDurationMinutes: 4
        )
    }

    private func makeContext(storeURL: URL? = nil) throws -> ModelContext {
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
        let configuration = if let storeURL {
            ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
        } else {
            ModelConfiguration(isStoredInMemoryOnly: true)
        }
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return ModelContext(container)
    }
}
