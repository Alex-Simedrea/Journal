import AnyLanguageModel
import CoreLocation
import Foundation
import MapKit

enum EntryLanguageModelService {
    static func extract(
        input: String,
        context: EntryPromptContext
    ) async throws -> EntryLanguageModelResult {
        LanguageModelResponseRecorder.shared.reset()
        let model = try JournalLanguageModelProvider.configuredModel(recordResponses: true)
        let references = EntryPromptReferences(
            places: context.places,
            people: context.people,
            historyEntries: context.selectedDayEntries,
            selectedDay: context.selectedDay
        )
        let currentCoordinate = context.currentLocation.coordinate
        let requestPrompt = prompt(
            input: input,
            context: context,
            references: references
        )
        let locationCoordinates = Dictionary(
            uniqueKeysWithValues: references.locationsByKey.map { key, reference in
                (
                    key,
                    TransitToolCoordinate(
                        latitude: reference.location.latitude,
                        longitude: reference.location.longitude
                    )
                )
            }
        )
        let toolRecorder = TransitToolRecorder(
            coordinatesByKey: locationCoordinates
        )
        let routingModes = Dictionary(
            context.transitTypes.flatMap { definition in
                ([definition.canonicalName] + definition.aliases).map {
                    (
                        TransitToolQueryValidator.normalize($0),
                        definition.routingMode
                    )
                }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let prohibitedToolQueries = Set(
            context.transitTypes.flatMap {
                [$0.canonicalName] + $0.aliases
            }.map(TransitToolQueryValidator.normalize)
        )
        let session = LanguageModelSession(
            model: model,
            tools: [
                SearchPlacesTool(
                    latitude: currentCoordinate.latitude,
                    longitude: currentCoordinate.longitude,
                    prohibitedQueries: prohibitedToolQueries,
                    recorder: toolRecorder
                ),
                SearchDestinationWithRoutesTool(
                    prohibitedQueries: prohibitedToolQueries,
                    recorder: toolRecorder
                ),
                EstimateRouteTool(
                    recorder: toolRecorder,
                    routingModesByTypeOrAlias: routingModes
                ),
                CompareRoutesTool(
                    recorder: toolRecorder,
                    routingModesByTypeOrAlias: routingModes
                ),
            ],
            instructions: instructions
        )

        let response: LanguageModelSession.Response<GeneratedEntryLog>
        do {
            response = try await session.respond(
                to: requestPrompt,
                generating: GeneratedEntryLog.self
            )
        } catch {
            LanguageModelResponseRecorder.shared.printLatestOutput()
            throw error
        }
        let toolSearches = await toolRecorder.recordedSearches()
        let validatedLog = try validate(response.content)
        return EntryLanguageModelResult(
            generatedLog: validatedLog,
            references: references,
            toolSearches: toolSearches,
            exchange: EntryModelExchange(
                instructions: instructions,
                prompt: requestPrompt,
                toolTranscript: toolTranscript(from: response.transcriptEntries),
                response: response.rawContent.jsonString
            )
        )
    }

    static func validate(
        _ generated: GeneratedEntryLog
    ) throws -> ValidatedGeneratedEntryLog {
        switch generated.entryKind {
        case .transit:
            guard let transit = generated.transit,
                  generated.placeVisit == nil else {
                throw EntryLanguageModelValidationError.mismatchedPayload
            }
            return .transit(
                transit,
                entryKindReview: generated.entryKindReview
            )
        case .placeVisit:
            guard let placeVisit = generated.placeVisit,
                  generated.transit == nil else {
                throw EntryLanguageModelValidationError.mismatchedPayload
            }
            return .placeVisit(
                placeVisit,
                entryKindReview: generated.entryKindReview
            )
        }
    }

}
