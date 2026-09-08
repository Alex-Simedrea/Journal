import Foundation
import SwiftData

/// Bridge schema: old composite locations and new payloads coexist until every
/// value has been copied and saved. Never collapse this into a type rename.
enum JournalSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [LogEntry.self, Person.self, Place.self, TransitDetails.self,
         PlaceVisitDetails.self, WorkoutDetails.self, TransitType.self,
         AutomationCandidate.self, ActiveJournalRecording.self]
    }
    @Model
    final class LogEntry {
        @Attribute(.unique) var id: UUID
        var kind: LogKind
        var createdAt: Date
        var startTime: Date?
        var endTime: Date?
        var startTimeZoneIdentifier: String
        var endTimeZoneIdentifier: String
        var creationTimeZoneIdentifier: String
        var timeConfidence: TimeConfidence
        var rawInputString: String?
        var automationCandidateID: UUID?
        var journalRecordingID: UUID?
        var needsReview: Bool
        var entryKindReviewReason: String?
        /// Boundary links intentionally use stable identifiers instead of SwiftData
        /// relationships. A link is stored on both entries, while the suppression
        /// identifiers remember an explicit unlink so launch-time reconciliation
        /// does not immediately recreate it.
        var linkedPreviousEntryID: UUID?
        var linkedNextEntryID: UUID?
        var suppressedPreviousEntryID: UUID?
        var suppressedNextEntryID: UUID?
        // SwiftData expands Codable structs into traversable schema key paths.
        // Observation can then try to materialize paths such as
        // `weather.condition`, which traps when the path crosses an optional
        // Codable value. Store these values as opaque JSON blobs and expose the
        // same typed API through computed properties instead.
        @Attribute(originalName: "photoReferences")
        private var photoReferencesData: Data?
        @Attribute(originalName: "weather")
        private var weatherData: Data?
        @Attribute(originalName: "endWeather")
        private var endWeatherData: Data?
        @Attribute(originalName: "dayWeatherRecords")
        private var dayWeatherRecordsData: Data?
    
        var photoReferences: [PhotoReference] {
            get {
                PersistedJSON.decode(
                    [PhotoReference].self,
                    from: photoReferencesData
                ) ?? []
            }
            set { photoReferencesData = PersistedJSON.encode(newValue) }
        }
    
        var weather: EntryWeather? {
            get { PersistedJSON.decode(EntryWeather.self, from: weatherData) }
            set { weatherData = newValue.flatMap(PersistedJSON.encode) }
        }
    
        var endWeather: EntryWeather? {
            get { PersistedJSON.decode(EntryWeather.self, from: endWeatherData) }
            set { endWeatherData = newValue.flatMap(PersistedJSON.encode) }
        }
    
        var dayWeatherRecords: [PersistedDayWeather] {
            get {
                PersistedJSON.decode(
                    [PersistedDayWeather].self,
                    from: dayWeatherRecordsData
                ) ?? []
            }
            set { dayWeatherRecordsData = PersistedJSON.encode(newValue) }
        }
        var wakeUpSourceSampleUUID: UUID?
        var sleepDurationSeconds: Double?
    
        @Relationship(deleteRule: .cascade) var transitDetails: TransitDetails?
        @Relationship(deleteRule: .cascade) var placeVisitDetails: PlaceVisitDetails?
        @Relationship(deleteRule: .cascade) var workoutDetails: WorkoutDetails?
    
        @Relationship(inverse: \Person.entries) var people: [Person] = []
    
        init(
            id: UUID,
            kind: LogKind,
            createdAt: Date,
            startTime: Date? = nil,
            endTime: Date? = nil,
            startTimeZoneIdentifier: String? = nil,
            endTimeZoneIdentifier: String? = nil,
            creationTimeZoneIdentifier: String = TimeZone.current.identifier,
            timeConfidence: TimeConfidence = .unresolved,
            rawInputString: String? = nil,
            automationCandidateID: UUID? = nil,
            journalRecordingID: UUID? = nil,
            photoReferences: [PhotoReference] = [],
            weather: EntryWeather? = nil,
            endWeather: EntryWeather? = nil,
            dayWeatherRecords: [PersistedDayWeather] = [],
            wakeUpSourceSampleUUID: UUID? = nil,
            sleepDurationSeconds: Double? = nil,
            entryKindReviewReason: String? = nil,
            linkedPreviousEntryID: UUID? = nil,
            linkedNextEntryID: UUID? = nil,
            suppressedPreviousEntryID: UUID? = nil,
            suppressedNextEntryID: UUID? = nil,
            needsReview: Bool
        ) {
            self.id = id
            self.kind = kind
            self.createdAt = createdAt
            self.startTime = startTime
            self.endTime = endTime
            self.startTimeZoneIdentifier = startTimeZoneIdentifier
                ?? creationTimeZoneIdentifier
            self.endTimeZoneIdentifier = endTimeZoneIdentifier
                ?? creationTimeZoneIdentifier
            self.creationTimeZoneIdentifier = creationTimeZoneIdentifier
            self.timeConfidence = timeConfidence
            self.rawInputString = rawInputString
            self.automationCandidateID = automationCandidateID
            self.journalRecordingID = journalRecordingID
            self.photoReferencesData = PersistedJSON.encode(photoReferences)
            self.weatherData = weather.flatMap(PersistedJSON.encode)
            self.endWeatherData = endWeather.flatMap(PersistedJSON.encode)
            self.dayWeatherRecordsData = PersistedJSON.encode(dayWeatherRecords)
            self.wakeUpSourceSampleUUID = wakeUpSourceSampleUUID
            self.sleepDurationSeconds = sleepDurationSeconds
            self.entryKindReviewReason = entryKindReviewReason
            self.linkedPreviousEntryID = linkedPreviousEntryID
            self.linkedNextEntryID = linkedNextEntryID
            self.suppressedPreviousEntryID = suppressedPreviousEntryID
            self.suppressedNextEntryID = suppressedNextEntryID
            self.needsReview = needsReview
        }
    
        convenience init(
            kind: LogKind,
            startTime: Date? = nil,
            endTime: Date? = nil,
            startTimeZoneIdentifier: String? = nil,
            endTimeZoneIdentifier: String? = nil,
            creationTimeZoneIdentifier: String = TimeZone.current.identifier,
            timeConfidence: TimeConfidence = .unresolved,
            rawInputString: String? = nil,
            automationCandidateID: UUID? = nil,
            journalRecordingID: UUID? = nil,
            photoReferences: [PhotoReference] = [],
            weather: EntryWeather? = nil,
            endWeather: EntryWeather? = nil,
            dayWeatherRecords: [PersistedDayWeather] = [],
            wakeUpSourceSampleUUID: UUID? = nil,
            sleepDurationSeconds: Double? = nil,
            entryKindReviewReason: String? = nil,
            linkedPreviousEntryID: UUID? = nil,
            linkedNextEntryID: UUID? = nil,
            suppressedPreviousEntryID: UUID? = nil,
            suppressedNextEntryID: UUID? = nil,
            needsReview: Bool
        ) {
            self.init(
                id: UUID(),
                kind: kind,
                createdAt: .now,
                startTime: startTime,
                endTime: endTime,
                startTimeZoneIdentifier: startTimeZoneIdentifier,
                endTimeZoneIdentifier: endTimeZoneIdentifier,
                creationTimeZoneIdentifier: creationTimeZoneIdentifier,
                timeConfidence: timeConfidence,
                rawInputString: rawInputString,
                automationCandidateID: automationCandidateID,
                journalRecordingID: journalRecordingID,
                photoReferences: photoReferences,
                weather: weather,
                endWeather: endWeather,
                dayWeatherRecords: dayWeatherRecords,
                wakeUpSourceSampleUUID: wakeUpSourceSampleUUID,
                sleepDurationSeconds: sleepDurationSeconds,
                entryKindReviewReason: entryKindReviewReason,
                linkedPreviousEntryID: linkedPreviousEntryID,
                linkedNextEntryID: linkedNextEntryID,
                suppressedPreviousEntryID: suppressedPreviousEntryID,
                suppressedNextEntryID: suppressedNextEntryID,
                needsReview: needsReview
            )
        }
    }

    @Model
    class Person {
        @Attribute(.unique) var id: UUID
        var name: String
        var aliases: [String]
        var contactIdentifier: String?
    
        var firstMetAt: Date?
        var firstMetPlace: Place?
    
        var lastMetAt: Date?
        var lastMetPlace: Place?
    
        var entries: [LogEntry] = []
    
        init(
            id: UUID,
            name: String,
            aliases: [String],
            contactIdentifier: String? = nil,
            firstMetAt: Date? = nil,
            firstMetPlace: Place? = nil,
            lastMetAt: Date? = nil,
            lastMetPlace: Place? = nil
        ) {
            self.id = id
            self.name = name
            self.aliases = aliases
            self.contactIdentifier = contactIdentifier
            self.firstMetAt = firstMetAt
            self.firstMetPlace = firstMetPlace
            self.lastMetAt = lastMetAt
            self.lastMetPlace = lastMetPlace
        }
    
        convenience init(
            name: String,
            contactIdentifier: String? = nil
        ) {
            self.init(
                id: UUID(),
                name: name,
                aliases: [],
                contactIdentifier: contactIdentifier
            )
        }
    }

    @Model
    class Place {
        @Attribute(.unique) var id: UUID
    
        var name: String
        var aliases: [String]
        var systemImage: PlaceSystemImage = PlaceSystemImage.mappin
    
        var location: Location
        var accuracyRadiusMeters: Double = 0
    
        var createdAt: Date
    
        init(
            id: UUID,
            name: String,
            aliases: [String],
            location: Location,
            systemImage: PlaceSystemImage,
            createdAt: Date,
            accuracyRadiusMeters: Double = 0
        ) {
            self.id = id
            self.name = name
            self.aliases = aliases
            self.location = location
            self.systemImage = systemImage
            self.createdAt = createdAt
            self.accuracyRadiusMeters = accuracyRadiusMeters
        }
    
        convenience init(
            name: String,
            location: Location,
            systemImage: PlaceSystemImage = .mappin,
            accuracyRadiusMeters: Double = 0
        ) {
            self.init(
                id: UUID(),
                name: name,
                aliases: [],
                location: location,
                systemImage: systemImage,
                createdAt: .now,
                accuracyRadiusMeters: accuracyRadiusMeters
            )
        }
    }

    @Model
    final class TransitDetails {
        var originLocationPayload: Data?
        var destinationLocationPayload: Data?

        var type: String  // TransitType.canonicalName
    
        var sourceOrganizationName: String?
        var sourceServiceIdentifier: String?
    
        var originPlace: Place?
        var originLocation: Location?
        var originRawText: String?
        var destinationPlace: Place?
        var destinationLocation: Location?
        var destinationRawText: String?
    
        var durationSource: DurationSource
        var distanceMeters: Double?
        var recordedRoute: [RecordedRoutePoint] = []
        var recordedMotion: [RecordedMotionObservation] = []
        var recordedTransitMode: RecordedTransitMode?
        var originCandidates: [LocationCandidate]
        var destinationCandidates: [LocationCandidate]
        var unresolvedPeople: [String]
        @Attribute(originalName: "fieldReviews")
        private var fieldReviewsData: Data?
    
        var fieldReviews: [TransitFieldReview] {
            get {
                PersistedJSON.decode(
                    [TransitFieldReview].self,
                    from: fieldReviewsData
                ) ?? []
            }
            set { fieldReviewsData = PersistedJSON.encode(newValue) }
        }
    
        init(
            type: String,
            sourceOrganizationName: String? = nil,
            sourceServiceIdentifier: String? = nil,
            originPlace: Place? = nil,
            originLocation: Location? = nil,
            originRawText: String? = nil,
            destinationPlace: Place? = nil,
            destinationLocation: Location? = nil,
            destinationRawText: String? = nil,
            durationSource: DurationSource = .unresolved,
            distanceMeters: Double? = nil,
            recordedRoute: [RecordedRoutePoint] = [],
            recordedMotion: [RecordedMotionObservation] = [],
            recordedTransitMode: RecordedTransitMode? = nil,
            originCandidates: [LocationCandidate] = [],
            destinationCandidates: [LocationCandidate] = [],
            unresolvedPeople: [String] = [],
            fieldReviews: [TransitFieldReview] = []
        ) {
            self.type = type
            self.sourceOrganizationName = sourceOrganizationName
            self.sourceServiceIdentifier = sourceServiceIdentifier
            self.originPlace = originPlace
            self.originLocation = originLocation ?? originPlace?.location
            self.originRawText = originRawText
            self.destinationPlace = destinationPlace
            self.destinationLocation = destinationLocation ?? destinationPlace?.location
            self.destinationRawText = destinationRawText
            self.durationSource = durationSource
            self.distanceMeters = distanceMeters
            self.recordedRoute = recordedRoute
            self.recordedMotion = recordedMotion
            self.recordedTransitMode = recordedTransitMode
            self.originCandidates = originCandidates
            self.destinationCandidates = destinationCandidates
            self.unresolvedPeople = unresolvedPeople
            self.fieldReviewsData = PersistedJSON.encode(fieldReviews)
        }
    
        func review(for field: TransitReviewField) -> TransitFieldReview? {
            fieldReviews.first { $0.field == field }
        }
    }

    @Model
    final class TransitType {
        @Attribute(.unique) var canonicalName: String
        var aliases: [String]
        var routingMode: TransitRoutingMode
    
        init(
            canonicalName: String,
            aliases: [String],
            routingMode: TransitRoutingMode = .automobile
        ) {
            self.canonicalName = canonicalName
            self.aliases = aliases
            self.routingMode = routingMode
        }
    }

    @Model
    final class PlaceVisitDetails {
        var locationPayload: Data?

        private var visitDescription: String?
        var place: Place?
        var location: Location?
        var placeRawText: String?
        var candidates: [LocationCandidate]
        var unresolvedPeople: [String]
        @Attribute(originalName: "fieldReviews")
        private var fieldReviewsData: Data?
    
        var fieldReviews: [PlaceVisitFieldReview] {
            get {
                PersistedJSON.decode(
                    [PlaceVisitFieldReview].self,
                    from: fieldReviewsData
                ) ?? []
            }
            set { fieldReviewsData = PersistedJSON.encode(newValue) }
        }
    
        init(
            description: String? = nil,
            place: Place? = nil,
            location: Location? = nil,
            placeRawText: String? = nil,
            candidates: [LocationCandidate] = [],
            unresolvedPeople: [String] = [],
            fieldReviews: [PlaceVisitFieldReview] = []
        ) {
            self.visitDescription = description
            self.place = place
            self.location = location ?? place?.location
            self.placeRawText = placeRawText
            self.candidates = candidates
            self.unresolvedPeople = unresolvedPeople
            self.fieldReviewsData = PersistedJSON.encode(fieldReviews)
        }
    
        var description: String? {
            get { visitDescription }
            set { visitDescription = newValue }
        }
    
        func review(for field: PlaceVisitReviewField) -> PlaceVisitFieldReview? {
            fieldReviews.first { $0.field == field }
        }
    }

    @Model
    final class WorkoutDetails {
        var sourceLocationPayload: Data?
        var originLocationPayload: Data?
        var destinationLocationPayload: Data?

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

    @Model
    final class AutomationCandidate {
        var visitLocationPayload: Data?
        var originLocationPayload: Data?
        var destinationLocationPayload: Data?

        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var sourceFingerprint: String
        var kind: AutomationCandidateKind
        var status: AutomationCandidateStatus
        var createdAt: Date
        var updatedAt: Date
        var startTime: Date
        var endTime: Date?
        var timeZoneIdentifier: String
    
        var visitLocation: Location?
        var visitHorizontalAccuracyMeters: Double?
        var visitPlaceID: UUID?
    
        var motionKind: MotionTransitKind?
        var motionConfidenceRawValue: Int?
        var originLocation: Location?
        var originPlaceID: UUID?
        var destinationLocation: Location?
        var destinationPlaceID: UUID?
    
        var acceptedEntryID: UUID?
        var provenanceRecordedAt: Date?
    
        init(
            id: UUID = UUID(),
            sourceFingerprint: String,
            kind: AutomationCandidateKind,
            status: AutomationCandidateStatus = .pending,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            startTime: Date,
            endTime: Date? = nil,
            timeZoneIdentifier: String = TimeZone.current.identifier,
            visitLocation: Location? = nil,
            visitHorizontalAccuracyMeters: Double? = nil,
            visitPlaceID: UUID? = nil,
            motionKind: MotionTransitKind? = nil,
            motionConfidenceRawValue: Int? = nil,
            originLocation: Location? = nil,
            originPlaceID: UUID? = nil,
            destinationLocation: Location? = nil,
            destinationPlaceID: UUID? = nil,
            acceptedEntryID: UUID? = nil,
            provenanceRecordedAt: Date? = nil
        ) {
            self.id = id
            self.sourceFingerprint = sourceFingerprint
            self.kind = kind
            self.status = status
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.startTime = startTime
            self.endTime = endTime
            self.timeZoneIdentifier = timeZoneIdentifier
            self.visitLocation = visitLocation
            self.visitHorizontalAccuracyMeters = visitHorizontalAccuracyMeters
            self.visitPlaceID = visitPlaceID
            self.motionKind = motionKind
            self.motionConfidenceRawValue = motionConfidenceRawValue
            self.originLocation = originLocation
            self.originPlaceID = originPlaceID
            self.destinationLocation = destinationLocation
            self.destinationPlaceID = destinationPlaceID
            self.acceptedEntryID = acceptedEntryID
            self.provenanceRecordedAt = provenanceRecordedAt
        }
    }

    @Model
    final class ActiveJournalRecording {
        @Attribute(.unique) var id: UUID
        var startedAt: Date
        var endedAt: Date?
        var lastUpdatedAt: Date
        var status: JournalRecordingStatus
        var startPath: JournalRecordingStartPath
        var mode: JournalRecordingMode = JournalRecordingMode.singleEntry
        var activityID: String?
        var approximateDistanceMeters: Double
        var currentMovement: RecordedTransitMode
        var points: [TrackedLocationPoint]
        var lastDiagnostic: String?
    
        init(
            id: UUID = UUID(),
            startedAt: Date = .now,
            endedAt: Date? = nil,
            lastUpdatedAt: Date = .now,
            status: JournalRecordingStatus = .starting,
            startPath: JournalRecordingStartPath,
            mode: JournalRecordingMode = .singleEntry,
            activityID: String? = nil,
            approximateDistanceMeters: Double = 0,
            currentMovement: RecordedTransitMode = .unknown,
            points: [TrackedLocationPoint] = [],
            lastDiagnostic: String? = nil
        ) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.lastUpdatedAt = lastUpdatedAt
            self.status = status
            self.startPath = startPath
            self.mode = mode
            self.activityID = activityID
            self.approximateDistanceMeters = approximateDistanceMeters
            self.currentMovement = currentMovement
            self.points = points
            self.lastDiagnostic = lastDiagnostic
        }
    }
}
