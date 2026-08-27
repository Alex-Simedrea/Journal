//
//  TransitDetails.swift
//  Journal
//
//  Created by Alexandru Simedrea on 11/07/2026.
//

import Foundation
import SwiftData

enum TransitRoutingMode: String, Codable, CaseIterable, Hashable, Sendable {
    case walking
    case automobile
}

enum DurationSource: String, Codable, Hashable, Sendable {
    case unresolved
    case mapkitCarFallback
    case mapkitWalking
    case manualOverride
}

nonisolated enum TransitReviewField: String, Codable, CaseIterable, Hashable, Sendable {
    case transitType
    case origin
    case destination
    case time
    case people
}

nonisolated struct TransitFieldReview: Codable, Hashable, Identifiable, Sendable {
    var field: TransitReviewField
    var reason: String

    var id: TransitReviewField { field }
}

nonisolated struct LocationCandidate: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var address: String?
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String?
    var cityName: String?
    var countryName: String?
    var countryCode: String?
    var distanceKilometers: Double?
    var walkingDurationMinutes: Double?
    var automobileDurationMinutes: Double?

    init(
        id: UUID = UUID(),
        name: String,
        address: String? = nil,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String? = nil,
        cityName: String? = nil,
        countryName: String? = nil,
        countryCode: String? = nil,
        distanceKilometers: Double? = nil,
        walkingDurationMinutes: Double? = nil,
        automobileDurationMinutes: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.cityName = cityName
        self.countryName = countryName
        self.countryCode = countryCode
        self.distanceKilometers = distanceKilometers
        self.walkingDurationMinutes = walkingDurationMinutes
        self.automobileDurationMinutes = automobileDurationMinutes
    }

    var location: Location {
        Location(
            latitude: latitude,
            longitude: longitude,
            displayName: name,
            formattedAddress: address,
            timeZoneIdentifier: timeZoneIdentifier,
            cityName: cityName,
            countryName: countryName,
            countryCode: countryCode
        )
    }
}

@Model
final class TransitDetails {
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
