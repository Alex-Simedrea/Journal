import Foundation

struct GuidedComposerContextRevision: Equatable, Hashable {
    let selectedDay: TimelineDayKey
    let places: [PlaceRevision]
    let people: [PersonRevision]
    let transitTypes: [TransitTypeRevision]
    let timelineRevision: Int

    static let unspecified = GuidedComposerContextRevision(
        selectedDay: .today(),
        places: [],
        people: [],
        transitTypes: [],
        timelineRevision: 0
    )

    struct PlaceRevision: Equatable, Hashable {
        let id: UUID
        let name: String
        let aliases: [String]
        let location: Location
        let systemImage: PlaceSystemImage
        let accuracyRadiusMeters: Double
    }

    struct PersonRevision: Equatable, Hashable {
        let id: UUID
        let name: String
        let aliases: [String]
        let contactIdentifier: String?
    }

    struct TransitTypeRevision: Equatable, Hashable {
        let canonicalName: String
        let aliases: [String]
        let routingMode: TransitRoutingMode
    }
}
