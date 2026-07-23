//
//  EntryLanguageModelService.swift
//  Journal
//

import AnyLanguageModel
import CoreLocation
import Foundation
import MapKit

@Generable(description: "Whether one extracted field is safe to accept without user confirmation")
nonisolated struct GeneratedFieldReview {
    @Guide(description: "True only when this specific field is unresolved or genuinely ambiguous")
    let needsReview: Bool
    @Guide(description: "A short, concrete explanation of the ambiguity. Nil when needsReview is false.")
    let reason: String?
}

@Generable(description: "The transit service or travel mode resolved against the supplied transit types")
nonisolated struct GeneratedTransitTypeResolution {
    @Guide(description: "The exact transit-type words from the user text")
    let rawText: String?
    @Guide(description: "A canonical name copied from TRANSIT TYPES, or the user's raw type only when genuinely novel")
    let canonicalName: String
    let review: GeneratedFieldReview
}

@Generable(description: "One entry location resolved to a saved place, historical endpoint, or MapKit result")
nonisolated struct GeneratedLocationResolution {
    @Guide(description: "Only the place phrase copied from the user text, without direction words")
    let rawText: String?
    @Guide(description: "An exact locationKey copied from SAVED PLACES, LOCATION HISTORY, or a MapKit tool result. Nil only when no defensible location exists.")
    let selectedLocationKey: String?
    @Guide(description: "Other plausible locationKey values, excluding selectedLocationKey. Empty when the selection is unambiguous.", .maximumCount(3))
    let alternativeLocationKeys: [String]
    let review: GeneratedFieldReview
}

@Generable(description: "How the model resolved the final trip timestamps")
nonisolated enum GeneratedTimeResolutionKind {
    case explicit
    case inferredFromHistory
    case inferredNearOrigin
    case inferredNearDestination
    case unresolved
}

@Generable(description: "Where the duration used to complete the final trip timestamps came from")
nonisolated enum GeneratedDurationSource {
    case none
    case mapkitWalking
    case mapkitCarFallback
}

@Generable(description: "The final time resolution produced in this same model session")
nonisolated struct GeneratedTimeResolution {
    @Guide(description: "The exact explicit temporal expression from the user text. Nil when timestamps were inferred from selected-day history or current proximity.")
    let rawText: String?
    @Guide(description: "How these final timestamps were resolved")
    let resolutionKind: GeneratedTimeResolutionKind
    @Guide(description: "Final ISO 8601 departure timestamp. When only arrival is explicit, derive departure by subtracting a MapKit route duration.")
    let startTimeISO8601: String?
    @Guide(description: "Final ISO 8601 arrival timestamp. When only departure is explicit, derive arrival by adding a MapKit route duration.")
    let endTimeISO8601: String?
    let durationSource: GeneratedDurationSource
    let review: GeneratedFieldReview
}

@Generable(description: "One person mentioned in the entry text")
nonisolated struct GeneratedPersonResolution {
    @Guide(description: "The exact person wording from the user text")
    let rawText: String
    @Guide(description: "An exact personKey copied from PEOPLE. Nil when no person matches.")
    let personKey: String?
    let review: GeneratedFieldReview
}

@Generable(description: "A structured extraction and resolution of exactly one transit log")
nonisolated struct GeneratedTransitLog {
    let transitType: GeneratedTransitTypeResolution
    let origin: GeneratedLocationResolution
    let destination: GeneratedLocationResolution
    let time: GeneratedTimeResolution
    @Guide(description: "Only people explicitly mentioned in the user text", .maximumCount(12))
    let people: [GeneratedPersonResolution]
}

@Generable(description: "Place-visit timestamps resolved from user wording and selected-day timeline continuity, never from proximity or route inference")
nonisolated struct GeneratedPlaceVisitTimeResolution {
    @Guide(description: "The exact temporal expression from the user text, including a duration such as 'for 10 minutes'; nil when history alone supplied the interval")
    let rawText: String?
    @Guide(description: "An ISO 8601 start timestamp supported by explicit wording or a defensible selected-day history placement")
    let startTimeISO8601: String?
    @Guide(description: "An ISO 8601 end timestamp supported by explicit wording or a defensible selected-day history placement")
    let endTimeISO8601: String?
    let review: GeneratedFieldReview
}

@Generable(description: "A structured extraction and resolution of exactly one place visit")
nonisolated struct GeneratedPlaceVisitLog {
    let place: GeneratedLocationResolution
    let time: GeneratedPlaceVisitTimeResolution
    @Guide(description: "Only people explicitly mentioned in the user text", .maximumCount(12))
    let people: [GeneratedPersonResolution]
}

@Generable(description: "The single entry type selected for this prompt")
nonisolated enum GeneratedEntryKind {
    case transit
    case placeVisit
}

@Generable(description: "One classified journal entry with exactly one matching typed payload")
nonisolated struct GeneratedEntryLog {
    let entryKind: GeneratedEntryKind
    let entryKindReview: GeneratedFieldReview
    @Guide(description: "Present only when entryKind is transit")
    let transit: GeneratedTransitLog?
    @Guide(description: "Present only when entryKind is placeVisit")
    let placeVisit: GeneratedPlaceVisitLog?
}

@Generable(description: "Which unresolved place role is being searched")
nonisolated enum GeneratedPlaceRole {
    case origin
    case destination
    case visit

    var label: String {
        switch self {
        case .origin: "origin"
        case .destination: "destination"
        case .visit: "visit"
        }
    }
}
