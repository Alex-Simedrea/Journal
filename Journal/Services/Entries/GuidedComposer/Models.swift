import Foundation

enum ComposerEntryKind: Equatable, Hashable, Sendable {
    case transit(canonicalName: String)
    case placeVisit(description: String?)
}

enum ComposerLocationRole: String, Equatable, Hashable, Sendable {
    case visit
    case origin
    case destination
}

enum ComposerTimeRole: String, Equatable, Hashable, Sendable {
    case start
    case end
}

enum ComposerConnector: String, Equatable, Hashable, Sendable {
    case at
    case from
    case since
    case to
    case until
    case forDuration = "for"
    case with
}

enum ComposerSlot: Equatable, Hashable, Sendable {
    case leading
    case connector
    case location(ComposerLocationRole)
    case time(ComposerTimeRole)
    case duration
    case person
}

enum ComposerResolutionState: Equatable, Hashable, Sendable {
    case softResolved
    case committed
}

enum ComposerValueRole: Equatable, Hashable, Sendable {
    case leading
    case connector
    case location(ComposerLocationRole)
    case time(ComposerTimeRole)
    case duration
    case person

    var slot: ComposerSlot {
        switch self {
        case .leading: .leading
        case .connector: .connector
        case .location(let role): .location(role)
        case .time(let role): .time(role)
        case .duration: .duration
        case .person: .person
        }
    }
}

enum ComposerLocationSource: Equatable, Hashable, Sendable {
    case savedPlace
    case timeline
    case mapKit
}

struct ComposerLocationCandidate: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let savedPlaceID: UUID?
    let displayName: String
    let aliases: [String]
    let location: Location
    let systemImage: PlaceSystemImage
    let accuracyRadiusMeters: Double
    let usageCount: Int
    let lastVisitedAt: Date?
    let source: ComposerLocationSource
    let searchTerms: [String]

    init(
        id: String,
        savedPlaceID: UUID? = nil,
        displayName: String,
        aliases: [String] = [],
        location: Location,
        systemImage: PlaceSystemImage = .mappin,
        accuracyRadiusMeters: Double = 0,
        usageCount: Int = 0,
        lastVisitedAt: Date? = nil,
        source: ComposerLocationSource,
        searchTerms: [String] = []
    ) {
        self.id = id
        self.savedPlaceID = savedPlaceID
        self.displayName = displayName
        self.aliases = aliases
        self.location = location
        self.systemImage = systemImage
        self.accuracyRadiusMeters = accuracyRadiusMeters
        self.usageCount = usageCount
        self.lastVisitedAt = lastVisitedAt
        self.source = source
        self.searchTerms = searchTerms
    }

    var allSearchTerms: [String] {
        [displayName]
            + aliases
            + searchTerms
            + [location.compactAddress, location.formattedAddress]
                .compactMap { $0 }
    }
}

struct ComposerPersonCandidate: Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let aliases: [String]
    let contactIdentifier: String?
    let usageCount: Int
}

enum ComposerTimeSource: Equatable, Hashable, Sendable {
    case explicit
    case history
    case nearOrigin
    case nearDestination
}

struct ComposerTimeValue: Equatable, Hashable, Sendable {
    let date: Date
    let timeZoneIdentifier: String
    let source: ComposerTimeSource
    let durationSource: DurationSource?
    let allowsOvernightRollover: Bool

    init(
        date: Date,
        timeZoneIdentifier: String,
        source: ComposerTimeSource,
        durationSource: DurationSource? = nil,
        allowsOvernightRollover: Bool = false
    ) {
        self.date = date
        self.timeZoneIdentifier = timeZoneIdentifier
        self.source = source
        self.durationSource = durationSource
        self.allowsOvernightRollover = allowsOvernightRollover
    }
}

struct ComposerTimePickerSeed: Equatable, Sendable {
    let id: UUID
    let role: ComposerTimeRole
    let date: Date
    let timeZoneIdentifier: String
}

struct ComposerDurationValue: Equatable, Hashable, Sendable {
    let interval: TimeInterval
    let source: DurationSource
}

enum ComposerTokenValue: Equatable, Hashable, Sendable {
    case leading(ComposerEntryKind)
    case connector(ComposerConnector)
    case location(ComposerLocationCandidate, ComposerLocationRole)
    case time(ComposerTimeValue, ComposerTimeRole)
    case duration(ComposerDurationValue)
    case person(ComposerPersonCandidate)
}

struct ComposerToken: Equatable, Identifiable, Sendable {
    let id: UUID
    var displayText: String
    var value: ComposerTokenValue

    init(
        id: UUID = UUID(),
        displayText: String,
        value: ComposerTokenValue
    ) {
        self.id = id
        self.displayText = displayText
        self.value = value
    }

    var role: ComposerValueRole {
        switch value {
        case .leading: .leading
        case .connector: .connector
        case .location(_, let role): .location(role)
        case .time(_, let role): .time(role)
        case .duration: .duration
        case .person: .person
        }
    }
}

struct ComposerSemanticBinding: Equatable, Identifiable, Sendable {
    let id: UUID
    var token: ComposerToken
    var range: Range<Int>

    init(
        id: UUID = UUID(),
        token: ComposerToken,
        range: Range<Int>
    ) {
        self.id = id
        self.token = token
        self.range = range
    }
}

struct ComposerSemanticSpan: Equatable, Identifiable, Sendable {
    let token: ComposerToken
    let range: Range<Int>
    let resolution: ComposerResolutionState

    var id: UUID { token.id }
}

struct ComposerParsedClauseRange: Equatable, Sendable {
    let range: Range<Int>
    let slot: ComposerSlot
}

struct ComposerParseAlternative: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let bindings: [ComposerSemanticBinding]
    let nextSlot: ComposerSlot
    let score: Int
}

struct ComposerContinuationContext: Equatable, Sendable {
    let slot: ComposerSlot
    let query: String
    let range: Range<Int>
}

struct ComposerParseSnapshot: Equatable, Sendable {
    let spans: [ComposerSemanticSpan]
    let clauseRanges: [ComposerParsedClauseRange]
    let activeRange: Range<Int>
    let activeSlot: ComposerSlot
    let activeQuery: String
    let continuation: ComposerContinuationContext?
    let alternatives: [ComposerParseAlternative]
    let isSyntaxValid: Bool

    var tokens: [ComposerToken] {
        spans.map(\.token)
    }

    var tokenRanges: [UUID: Range<Int>] {
        Dictionary(uniqueKeysWithValues: spans.map { ($0.token.id, $0.range) })
    }
}

struct ComposerTransitTypeCandidate: Equatable {
    let canonicalName: String
    let aliases: [String]
    let routingMode: TransitRoutingMode
}
