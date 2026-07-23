import AnyLanguageModel
import CoreLocation
import Foundation
import MapKit

struct EntryModelExchange {
    let instructions: String
    let prompt: String
    let toolTranscript: String?
    let response: String
}

enum ValidatedGeneratedEntryLog {
    case transit(GeneratedTransitLog, entryKindReview: GeneratedFieldReview)
    case placeVisit(GeneratedPlaceVisitLog, entryKindReview: GeneratedFieldReview)
}

enum EntryLanguageModelValidationError: LocalizedError {
    case mismatchedPayload

    var errorDescription: String? {
        String(localized: "The model returned an entry type that did not match its details.")
    }
}

struct EntryLanguageModelResult {
    let generatedLog: ValidatedGeneratedEntryLog
    let references: EntryPromptReferences
    let toolSearches: [TransitToolSearch]
    let exchange: EntryModelExchange
}
