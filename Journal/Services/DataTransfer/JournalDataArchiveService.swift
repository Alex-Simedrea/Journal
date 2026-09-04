import Foundation
import SwiftData

struct JournalDataArchive: Codable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let exportedAt: Date
    let places: [PlaceRecord]
    let people: [PersonRecord]
    let transitTypes: [TransitTypeRecord]
    let entries: [EntryRecord]
    let automationCandidates: [AutomationCandidateRecord]
    let orphanTransitDetails: [TransitDetailsRecord]
    let orphanPlaceVisitDetails: [PlaceVisitDetailsRecord]
    let orphanWorkoutDetails: [WorkoutDetailsRecord]

    struct PlaceRecord: Codable {
        let id: UUID
        let name: String
        let aliases: [String]
        let systemImage: PlaceSystemImage
        let location: Location
        let accuracyRadiusMeters: Double
        let createdAt: Date
    }

    struct PersonRecord: Codable {
        let id: UUID
        let name: String
        let aliases: [String]
        let contactIdentifier: String?
        let firstMetAt: Date?
        let firstMetPlaceID: UUID?
        let lastMetAt: Date?
        let lastMetPlaceID: UUID?
    }

    struct TransitTypeRecord: Codable {
        let canonicalName: String
        let aliases: [String]
        let routingMode: TransitRoutingMode
    }

    struct EntryRecord: Codable {
        let id: UUID
        let kind: LogKind
        let createdAt: Date
        let startTime: Date?
        let endTime: Date?
        let startTimeZoneIdentifier: String
        let endTimeZoneIdentifier: String
        let creationTimeZoneIdentifier: String
        let timeConfidence: TimeConfidence
        let rawInputString: String?
        let automationCandidateID: UUID?
        let journalRecordingID: UUID?
        let needsReview: Bool
        let entryKindReviewReason: String?
        let linkedPreviousEntryID: UUID?
        let linkedNextEntryID: UUID?
        let suppressedPreviousEntryID: UUID?
        let suppressedNextEntryID: UUID?
        let photoReferences: [PhotoReference]
        let weather: EntryWeather?
        let endWeather: EntryWeather?
        let dayWeatherRecords: [PersistedDayWeather]
        let wakeUpSourceSampleUUID: UUID?
        let sleepDurationSeconds: Double?
        let personIDs: [UUID]
        let transitDetails: TransitDetailsRecord?
        let placeVisitDetails: PlaceVisitDetailsRecord?
        let workoutDetails: WorkoutDetailsRecord?
    }

    struct TransitDetailsRecord: Codable {
        let type: String
        let sourceOrganizationName: String?
        let sourceServiceIdentifier: String?
        let originPlaceID: UUID?
        let originLocation: Location?
        let originRawText: String?
        let destinationPlaceID: UUID?
        let destinationLocation: Location?
        let destinationRawText: String?
        let durationSource: DurationSource
        let distanceMeters: Double?
        let recordedRoute: [RecordedRoutePoint]?
        let recordedMotion: [RecordedMotionObservation]?
        let recordedTransitMode: RecordedTransitMode?
        let originCandidates: [LocationCandidate]
        let destinationCandidates: [LocationCandidate]
        let unresolvedPeople: [String]
        let fieldReviews: [TransitFieldReview]
    }

    struct PlaceVisitDetailsRecord: Codable {
        let description: String?
        let placeID: UUID?
        let location: Location?
        let placeRawText: String?
        let candidates: [LocationCandidate]
        let unresolvedPeople: [String]
        let fieldReviews: [PlaceVisitFieldReview]
    }

    struct WorkoutDetailsRecord: Codable {
        let healthKitWorkoutUUID: UUID
        let activityTypeRawValue: Int
        let activityName: String
        let movementKind: WorkoutMovementKind
        let distanceMeters: Double?
        let activeEnergyKilocalories: Double?
        let routeImportState: WorkoutRouteImportState
        let sourceLocation: Location?
        let originLocation: Location?
        let destinationLocation: Location?
        let placeID: UUID?
        let originPlaceID: UUID?
        let destinationPlaceID: UUID?
        let placeResolutionSource: WorkoutPlaceResolutionSource
        let originResolutionSource: WorkoutPlaceResolutionSource
        let destinationResolutionSource: WorkoutPlaceResolutionSource
        let fieldReviews: [WorkoutFieldReview]
    }

    struct AutomationCandidateRecord: Codable {
        let id: UUID
        let sourceFingerprint: String
        let kind: AutomationCandidateKind
        let status: AutomationCandidateStatus
        let createdAt: Date
        let updatedAt: Date
        let startTime: Date
        let endTime: Date?
        let timeZoneIdentifier: String
        let visitLocation: Location?
        let visitHorizontalAccuracyMeters: Double?
        let visitPlaceID: UUID?
        let motionKind: MotionTransitKind?
        let motionConfidenceRawValue: Int?
        let originLocation: Location?
        let originPlaceID: UUID?
        let destinationLocation: Location?
        let destinationPlaceID: UUID?
        let acceptedEntryID: UUID?
        let provenanceRecordedAt: Date?
    }
}

@MainActor
enum JournalDataArchiveService {
    static func exportData(from modelContext: ModelContext) throws -> Data {
        let archive = try makeArchive(from: modelContext)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> JournalDataArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        let archive = try decoder.decode(JournalDataArchive.self, from: data)
        try validate(archive)
        return archive
    }

    static func replaceAllData(
        with archive: JournalDataArchive,
        in modelContext: ModelContext
    ) throws {
        try validate(archive)
        let imported = try makeImportedGraph(from: archive)

        do {
            try deleteExistingData(in: modelContext)
            // Commit removals before inserting records with the same unique
            // IDs. Otherwise SwiftData can treat the restore as an upsert and
            // try to merge nested Codable values such as EntryWeather using
            // its unsupported key-path append machinery.
            try modelContext.save()

            for place in imported.places { modelContext.insert(place) }
            for person in imported.people { modelContext.insert(person) }
            for transitType in imported.transitTypes {
                modelContext.insert(transitType)
            }
            for entry in imported.entries { modelContext.insert(entry) }
            for candidate in imported.automationCandidates {
                modelContext.insert(candidate)
            }
            for details in imported.orphanTransitDetails {
                modelContext.insert(details)
            }
            for details in imported.orphanPlaceVisitDetails {
                modelContext.insert(details)
            }
            for details in imported.orphanWorkoutDetails {
                modelContext.insert(details)
            }
            _ = try EntryLinkingService.reconcile(in: modelContext)
            try modelContext.save()
            NotificationCenter.default.post(
                name: .automationCandidatesDidChange,
                object: nil
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func makeArchive(
        from modelContext: ModelContext
    ) throws -> JournalDataArchive {
        let places = try modelContext.fetch(FetchDescriptor<Place>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let people = try modelContext.fetch(FetchDescriptor<Person>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let transitTypes = try modelContext.fetch(
            FetchDescriptor<TransitType>()
        ).sorted { $0.canonicalName < $1.canonicalName }
        let entries = try modelContext.fetch(FetchDescriptor<LogEntry>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let candidates = try modelContext.fetch(
            FetchDescriptor<AutomationCandidate>()
        ).sorted { $0.id.uuidString < $1.id.uuidString }
        let referencedTransitDetails = Set(
            entries.compactMap(\.transitDetails).map(ObjectIdentifier.init)
        )
        let referencedVisitDetails = Set(
            entries.compactMap(\.placeVisitDetails).map(ObjectIdentifier.init)
        )
        let referencedWorkoutDetails = Set(
            entries.compactMap(\.workoutDetails).map(ObjectIdentifier.init)
        )
        let orphanTransitDetails = try modelContext.fetch(
            FetchDescriptor<TransitDetails>()
        ).filter {
            !referencedTransitDetails.contains(ObjectIdentifier($0))
        }
        let orphanVisitDetails = try modelContext.fetch(
            FetchDescriptor<PlaceVisitDetails>()
        ).filter {
            !referencedVisitDetails.contains(ObjectIdentifier($0))
        }
        let orphanWorkoutDetails = try modelContext.fetch(
            FetchDescriptor<WorkoutDetails>()
        ).filter {
            !referencedWorkoutDetails.contains(ObjectIdentifier($0))
        }

        return JournalDataArchive(
            formatVersion: JournalDataArchive.currentFormatVersion,
            exportedAt: .now,
            places: places.map(archivePlace),
            people: people.map(archivePerson),
            transitTypes: transitTypes.map(archiveTransitType),
            entries: entries.map(archiveEntry),
            automationCandidates: candidates.map(archiveCandidate),
            orphanTransitDetails: orphanTransitDetails.map(
                archiveTransitDetails
            ),
            orphanPlaceVisitDetails: orphanVisitDetails.map(
                archivePlaceVisitDetails
            ),
            orphanWorkoutDetails: orphanWorkoutDetails.map(
                archiveWorkoutDetails
            )
        )
    }

    private static func archivePlace(_ place: Place) -> JournalDataArchive.PlaceRecord {
        .init(
            id: place.id,
            name: place.name,
            aliases: place.aliases,
            systemImage: place.systemImage,
            location: place.location,
            accuracyRadiusMeters: place.accuracyRadiusMeters,
            createdAt: place.createdAt
        )
    }

    private static func archivePerson(
        _ person: Person
    ) -> JournalDataArchive.PersonRecord {
        .init(
            id: person.id,
            name: person.name,
            aliases: person.aliases,
            contactIdentifier: person.contactIdentifier,
            firstMetAt: person.firstMetAt,
            firstMetPlaceID: person.firstMetPlace?.id,
            lastMetAt: person.lastMetAt,
            lastMetPlaceID: person.lastMetPlace?.id
        )
    }

    private static func archiveTransitType(
        _ type: TransitType
    ) -> JournalDataArchive.TransitTypeRecord {
        .init(
            canonicalName: type.canonicalName,
            aliases: type.aliases,
            routingMode: type.routingMode
        )
    }

    private static func archiveEntry(
        _ entry: LogEntry
    ) -> JournalDataArchive.EntryRecord {
        .init(
            id: entry.id,
            kind: entry.kind,
            createdAt: entry.createdAt,
            startTime: entry.startTime,
            endTime: entry.endTime,
            startTimeZoneIdentifier: entry.startTimeZoneIdentifier,
            endTimeZoneIdentifier: entry.endTimeZoneIdentifier,
            creationTimeZoneIdentifier: entry.creationTimeZoneIdentifier,
            timeConfidence: entry.timeConfidence,
            rawInputString: entry.rawInputString,
            automationCandidateID: entry.automationCandidateID,
            journalRecordingID: entry.journalRecordingID,
            needsReview: entry.needsReview,
            entryKindReviewReason: entry.entryKindReviewReason,
            linkedPreviousEntryID: entry.linkedPreviousEntryID,
            linkedNextEntryID: entry.linkedNextEntryID,
            suppressedPreviousEntryID: entry.suppressedPreviousEntryID,
            suppressedNextEntryID: entry.suppressedNextEntryID,
            photoReferences: entry.photoReferences,
            weather: entry.weather,
            endWeather: entry.endWeather,
            dayWeatherRecords: entry.dayWeatherRecords,
            wakeUpSourceSampleUUID: entry.wakeUpSourceSampleUUID,
            sleepDurationSeconds: entry.sleepDurationSeconds,
            personIDs: entry.people.map(\.id).sorted {
                $0.uuidString < $1.uuidString
            },
            transitDetails: entry.transitDetails.map(archiveTransitDetails),
            placeVisitDetails: entry.placeVisitDetails.map(
                archivePlaceVisitDetails
            ),
            workoutDetails: entry.workoutDetails.map(archiveWorkoutDetails)
        )
    }

    private static func archiveTransitDetails(
        _ details: TransitDetails
    ) -> JournalDataArchive.TransitDetailsRecord {
        .init(
            type: details.type,
            sourceOrganizationName: details.sourceOrganizationName,
            sourceServiceIdentifier: details.sourceServiceIdentifier,
            originPlaceID: details.originPlace?.id,
            originLocation: details.originLocation,
            originRawText: details.originRawText,
            destinationPlaceID: details.destinationPlace?.id,
            destinationLocation: details.destinationLocation,
            destinationRawText: details.destinationRawText,
            durationSource: details.durationSource,
            distanceMeters: details.distanceMeters,
            recordedRoute: details.recordedRoute,
            recordedMotion: details.recordedMotion,
            recordedTransitMode: details.recordedTransitMode,
            originCandidates: details.originCandidates,
            destinationCandidates: details.destinationCandidates,
            unresolvedPeople: details.unresolvedPeople,
            fieldReviews: details.fieldReviews
        )
    }

    private static func archivePlaceVisitDetails(
        _ details: PlaceVisitDetails
    ) -> JournalDataArchive.PlaceVisitDetailsRecord {
        .init(
            description: details.description,
            placeID: details.place?.id,
            location: details.location,
            placeRawText: details.placeRawText,
            candidates: details.candidates,
            unresolvedPeople: details.unresolvedPeople,
            fieldReviews: details.fieldReviews
        )
    }

    private static func archiveWorkoutDetails(
        _ details: WorkoutDetails
    ) -> JournalDataArchive.WorkoutDetailsRecord {
        .init(
            healthKitWorkoutUUID: details.healthKitWorkoutUUID,
            activityTypeRawValue: details.activityTypeRawValue,
            activityName: details.activityName,
            movementKind: details.movementKind,
            distanceMeters: details.distanceMeters,
            activeEnergyKilocalories: details.activeEnergyKilocalories,
            routeImportState: details.routeImportState,
            sourceLocation: details.sourceLocation,
            originLocation: details.originLocation,
            destinationLocation: details.destinationLocation,
            placeID: details.place?.id,
            originPlaceID: details.originPlace?.id,
            destinationPlaceID: details.destinationPlace?.id,
            placeResolutionSource: details.placeResolutionSource,
            originResolutionSource: details.originResolutionSource,
            destinationResolutionSource: details.destinationResolutionSource,
            fieldReviews: details.fieldReviews
        )
    }

    private static func archiveCandidate(
        _ candidate: AutomationCandidate
    ) -> JournalDataArchive.AutomationCandidateRecord {
        .init(
            id: candidate.id,
            sourceFingerprint: candidate.sourceFingerprint,
            kind: candidate.kind,
            status: candidate.status,
            createdAt: candidate.createdAt,
            updatedAt: candidate.updatedAt,
            startTime: candidate.startTime,
            endTime: candidate.endTime,
            timeZoneIdentifier: candidate.timeZoneIdentifier,
            visitLocation: candidate.visitLocation,
            visitHorizontalAccuracyMeters:
                candidate.visitHorizontalAccuracyMeters,
            visitPlaceID: candidate.visitPlaceID,
            motionKind: candidate.motionKind,
            motionConfidenceRawValue: candidate.motionConfidenceRawValue,
            originLocation: candidate.originLocation,
            originPlaceID: candidate.originPlaceID,
            destinationLocation: candidate.destinationLocation,
            destinationPlaceID: candidate.destinationPlaceID,
            acceptedEntryID: candidate.acceptedEntryID,
            provenanceRecordedAt: candidate.provenanceRecordedAt
        )
    }

    private struct ImportedGraph {
        let places: [Place]
        let people: [Person]
        let transitTypes: [TransitType]
        let entries: [LogEntry]
        let automationCandidates: [AutomationCandidate]
        let orphanTransitDetails: [TransitDetails]
        let orphanPlaceVisitDetails: [PlaceVisitDetails]
        let orphanWorkoutDetails: [WorkoutDetails]
    }

    private static func makeImportedGraph(
        from archive: JournalDataArchive
    ) throws -> ImportedGraph {
        let places = archive.places.map {
            Place(
                id: $0.id,
                name: $0.name,
                aliases: $0.aliases,
                location: $0.location,
                systemImage: $0.systemImage,
                createdAt: $0.createdAt,
                accuracyRadiusMeters: $0.accuracyRadiusMeters
            )
        }
        let placesByID = Dictionary(
            uniqueKeysWithValues: places.map { ($0.id, $0) }
        )
        let people = try archive.people.map { record in
            Person(
                id: record.id,
                name: record.name,
                aliases: record.aliases,
                contactIdentifier: record.contactIdentifier,
                firstMetAt: record.firstMetAt,
                firstMetPlace: try resolve(
                    record.firstMetPlaceID,
                    from: placesByID,
                    relationship: "person.firstMetPlace"
                ),
                lastMetAt: record.lastMetAt,
                lastMetPlace: try resolve(
                    record.lastMetPlaceID,
                    from: placesByID,
                    relationship: "person.lastMetPlace"
                )
            )
        }
        let peopleByID = Dictionary(
            uniqueKeysWithValues: people.map { ($0.id, $0) }
        )
        let transitTypes = archive.transitTypes.map {
            TransitType(
                canonicalName: $0.canonicalName,
                aliases: $0.aliases,
                routingMode: $0.routingMode
            )
        }
        let entries = try archive.entries.map { record in
            let entry = LogEntry(
                id: record.id,
                kind: record.kind,
                createdAt: record.createdAt,
                startTime: record.startTime,
                endTime: record.endTime,
                startTimeZoneIdentifier: record.startTimeZoneIdentifier,
                endTimeZoneIdentifier: record.endTimeZoneIdentifier,
                creationTimeZoneIdentifier: record.creationTimeZoneIdentifier,
                timeConfidence: record.timeConfidence,
                rawInputString: record.rawInputString,
                automationCandidateID: record.automationCandidateID,
                journalRecordingID: record.journalRecordingID,
                photoReferences: record.photoReferences,
                weather: record.weather,
                endWeather: record.endWeather,
                dayWeatherRecords: record.dayWeatherRecords,
                wakeUpSourceSampleUUID: record.wakeUpSourceSampleUUID,
                sleepDurationSeconds: record.sleepDurationSeconds,
                entryKindReviewReason: record.entryKindReviewReason,
                linkedPreviousEntryID: record.linkedPreviousEntryID,
                linkedNextEntryID: record.linkedNextEntryID,
                suppressedPreviousEntryID: record.suppressedPreviousEntryID,
                suppressedNextEntryID: record.suppressedNextEntryID,
                needsReview: record.needsReview
            )
            entry.people = try record.personIDs.map { id in
                guard let person = peopleByID[id] else {
                    throw JournalDataArchiveError.missingRelationship(
                        "entry.persons -> \(id.uuidString)"
                    )
                }
                return person
            }
            entry.transitDetails = try record.transitDetails.map {
                try importTransitDetails($0, placesByID: placesByID)
            }
            entry.placeVisitDetails = try record.placeVisitDetails.map {
                try importPlaceVisitDetails($0, placesByID: placesByID)
            }
            entry.workoutDetails = try record.workoutDetails.map {
                try importWorkoutDetails($0, placesByID: placesByID)
            }
            return entry
        }
        let candidates = archive.automationCandidates.map {
            AutomationCandidate(
                id: $0.id,
                sourceFingerprint: $0.sourceFingerprint,
                kind: $0.kind,
                status: $0.status,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                startTime: $0.startTime,
                endTime: $0.endTime,
                timeZoneIdentifier: $0.timeZoneIdentifier,
                visitLocation: $0.visitLocation,
                visitHorizontalAccuracyMeters:
                    $0.visitHorizontalAccuracyMeters,
                visitPlaceID: $0.visitPlaceID,
                motionKind: $0.motionKind,
                motionConfidenceRawValue: $0.motionConfidenceRawValue,
                originLocation: $0.originLocation,
                originPlaceID: $0.originPlaceID,
                destinationLocation: $0.destinationLocation,
                destinationPlaceID: $0.destinationPlaceID,
                acceptedEntryID: $0.acceptedEntryID,
                provenanceRecordedAt: $0.provenanceRecordedAt
            )
        }
        let orphanTransitDetails = try archive.orphanTransitDetails.map {
            try importTransitDetails($0, placesByID: placesByID)
        }
        let orphanVisitDetails = try archive.orphanPlaceVisitDetails.map {
            try importPlaceVisitDetails($0, placesByID: placesByID)
        }
        let orphanWorkoutDetails = try archive.orphanWorkoutDetails.map {
            try importWorkoutDetails($0, placesByID: placesByID)
        }
        return ImportedGraph(
            places: places,
            people: people,
            transitTypes: transitTypes,
            entries: entries,
            automationCandidates: candidates,
            orphanTransitDetails: orphanTransitDetails,
            orphanPlaceVisitDetails: orphanVisitDetails,
            orphanWorkoutDetails: orphanWorkoutDetails
        )
    }

    private static func importTransitDetails(
        _ record: JournalDataArchive.TransitDetailsRecord,
        placesByID: [UUID: Place]
    ) throws -> TransitDetails {
        TransitDetails(
            type: record.type,
            sourceOrganizationName: record.sourceOrganizationName,
            sourceServiceIdentifier: record.sourceServiceIdentifier,
            originPlace: try resolve(
                record.originPlaceID,
                from: placesByID,
                relationship: "transit.originPlace"
            ),
            originLocation: record.originLocation,
            originRawText: record.originRawText,
            destinationPlace: try resolve(
                record.destinationPlaceID,
                from: placesByID,
                relationship: "transit.destinationPlace"
            ),
            destinationLocation: record.destinationLocation,
            destinationRawText: record.destinationRawText,
            durationSource: record.durationSource,
            distanceMeters: record.distanceMeters,
            recordedRoute: record.recordedRoute ?? [],
            recordedMotion: record.recordedMotion ?? [],
            recordedTransitMode: record.recordedTransitMode,
            originCandidates: record.originCandidates,
            destinationCandidates: record.destinationCandidates,
            unresolvedPeople: record.unresolvedPeople,
            fieldReviews: record.fieldReviews
        )
    }

    private static func importPlaceVisitDetails(
        _ record: JournalDataArchive.PlaceVisitDetailsRecord,
        placesByID: [UUID: Place]
    ) throws -> PlaceVisitDetails {
        PlaceVisitDetails(
            description: record.description,
            place: try resolve(
                record.placeID,
                from: placesByID,
                relationship: "visit.place"
            ),
            location: record.location,
            placeRawText: record.placeRawText,
            candidates: record.candidates,
            unresolvedPeople: record.unresolvedPeople,
            fieldReviews: record.fieldReviews
        )
    }

    private static func importWorkoutDetails(
        _ record: JournalDataArchive.WorkoutDetailsRecord,
        placesByID: [UUID: Place]
    ) throws -> WorkoutDetails {
        WorkoutDetails(
            healthKitWorkoutUUID: record.healthKitWorkoutUUID,
            activityTypeRawValue: record.activityTypeRawValue,
            activityName: record.activityName,
            movementKind: record.movementKind,
            distanceMeters: record.distanceMeters,
            activeEnergyKilocalories: record.activeEnergyKilocalories,
            routeImportState: record.routeImportState,
            sourceLocation: record.sourceLocation,
            originLocation: record.originLocation,
            destinationLocation: record.destinationLocation,
            place: try resolve(
                record.placeID,
                from: placesByID,
                relationship: "workout.place"
            ),
            originPlace: try resolve(
                record.originPlaceID,
                from: placesByID,
                relationship: "workout.originPlace"
            ),
            destinationPlace: try resolve(
                record.destinationPlaceID,
                from: placesByID,
                relationship: "workout.destinationPlace"
            ),
            placeResolutionSource: record.placeResolutionSource,
            originResolutionSource: record.originResolutionSource,
            destinationResolutionSource:
                record.destinationResolutionSource,
            fieldReviews: record.fieldReviews
        )
    }

    private static func deleteExistingData(
        in modelContext: ModelContext
    ) throws {
        for entry in try modelContext.fetch(FetchDescriptor<LogEntry>()) {
            modelContext.delete(entry)
        }
        for details in try modelContext.fetch(
            FetchDescriptor<TransitDetails>()
        ) {
            modelContext.delete(details)
        }
        for details in try modelContext.fetch(
            FetchDescriptor<PlaceVisitDetails>()
        ) {
            modelContext.delete(details)
        }
        for details in try modelContext.fetch(
            FetchDescriptor<WorkoutDetails>()
        ) {
            modelContext.delete(details)
        }
        for person in try modelContext.fetch(FetchDescriptor<Person>()) {
            modelContext.delete(person)
        }
        for place in try modelContext.fetch(FetchDescriptor<Place>()) {
            modelContext.delete(place)
        }
        for transitType in try modelContext.fetch(
            FetchDescriptor<TransitType>()
        ) {
            modelContext.delete(transitType)
        }
        for candidate in try modelContext.fetch(
            FetchDescriptor<AutomationCandidate>()
        ) {
            modelContext.delete(candidate)
        }
    }

    private static func validate(_ archive: JournalDataArchive) throws {
        guard archive.formatVersion == JournalDataArchive.currentFormatVersion
        else {
            throw JournalDataArchiveError.unsupportedVersion(
                archive.formatVersion
            )
        }
        try requireUnique(archive.places.map(\.id), name: "place IDs")
        try requireUnique(archive.people.map(\.id), name: "person IDs")
        try requireUnique(archive.entries.map(\.id), name: "entry IDs")
        try requireUnique(
            archive.transitTypes.map(\.canonicalName),
            name: "transit type names"
        )
        try requireUnique(
            archive.automationCandidates.map(\.id),
            name: "automation candidate IDs"
        )
        try requireUnique(
            archive.automationCandidates.map(\.sourceFingerprint),
            name: "automation fingerprints"
        )
        try requireUnique(
            archive.entries.compactMap {
                $0.workoutDetails?.healthKitWorkoutUUID
            },
            name: "HealthKit workout IDs"
        )
    }

    private static func requireUnique<Value: Hashable>(
        _ values: [Value],
        name: String
    ) throws {
        guard Set(values).count == values.count else {
            throw JournalDataArchiveError.duplicateValue(name)
        }
    }

    private static func resolve<Value>(
        _ id: UUID?,
        from values: [UUID: Value],
        relationship: String
    ) throws -> Value? {
        guard let id else { return nil }
        guard let value = values[id] else {
            throw JournalDataArchiveError.missingRelationship(
                "\(relationship) -> \(id.uuidString)"
            )
        }
        return value
    }
}

enum JournalDataArchiveError: LocalizedError {
    case unsupportedVersion(Int)
    case duplicateValue(String)
    case missingRelationship(String)
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "This backup uses unsupported format version \(version)."
        case .duplicateValue(let name):
            "The backup contains duplicate \(name)."
        case .missingRelationship(let relationship):
            "The backup contains a missing relationship: \(relationship)."
        case .emptyFile:
            "The selected backup file is empty."
        }
    }
}
