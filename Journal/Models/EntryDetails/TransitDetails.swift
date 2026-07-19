//
//  TransitDetails.swift
//  Journal
//
//  Created by Alexandru Simedrea on 11/07/2026.
//

import Foundation
import SwiftData

enum TransitRoutingMode: String, Codable, CaseIterable {
    case walking
    case automobile
}

enum DurationSource: String, Codable {
    case unresolved
    case mapkitCarFallback
    case mapkitWalking
    case manualOverride
}

enum TransitReviewField: String, Codable, CaseIterable, Hashable {
    case transitType
    case origin
    case destination
    case time
    case people
}

struct TransitFieldReview: Codable, Hashable, Identifiable {
    var field: TransitReviewField
    var reason: String

    var id: TransitReviewField { field }
}

struct LocationCandidate: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var address: String?
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String?
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
            timeZoneIdentifier: timeZoneIdentifier
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
    var originCandidates: [LocationCandidate]
    var destinationCandidates: [LocationCandidate]
    var unresolvedPeople: [String]
    var fieldReviews: [TransitFieldReview] = []

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
        self.originCandidates = originCandidates
        self.destinationCandidates = destinationCandidates
        self.unresolvedPeople = unresolvedPeople
        self.fieldReviews = fieldReviews
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
