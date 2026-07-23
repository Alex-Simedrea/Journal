import AnyLanguageModel
import CoreLocation
import Foundation
import MapKit

nonisolated enum TransitToolQueryValidator {
    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
    }
}

nonisolated enum TransitToolOutputFormatter {
    static func string(_ search: TransitToolSearch) -> String {
        encode(
            TransitToolOutput(
                role: search.role.label,
                query: search.query,
                error: nil,
                candidates: search.candidates.map(TransitToolCandidateOutput.init)
            )
        )
    }

    static func error(
        role: GeneratedPlaceRole,
        query: String,
        message: String
    ) -> String {
        encode(
            TransitToolOutput(
                role: role.label,
                query: query,
                error: message,
                candidates: []
            )
        )
    }

    private static func encode(_ output: TransitToolOutput) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(output),
              let value = String(data: data, encoding: .utf8) else {
            return #"{"error":"Could not encode MapKit results"}"#
        }
        return value
    }
}

nonisolated private struct TransitToolOutput: Encodable {
    let role: String
    let query: String
    let error: String?
    let candidates: [TransitToolCandidateOutput]
}

nonisolated private struct TransitToolCandidateOutput: Encodable {
    let locationKey: String
    let name: String
    let address: String?
    let timeZoneIdentifier: String?
    let distanceKilometers: Double?
    let walkingDurationMinutes: Double?
    let automobileDurationMinutes: Double?

    init(_ candidate: TransitToolCandidate) {
        locationKey = candidate.candidateKey
        name = candidate.result.name
        address = candidate.result.address
        timeZoneIdentifier = candidate.result.timeZoneIdentifier
        distanceKilometers = candidate.result.distanceKilometers
        walkingDurationMinutes = candidate.result.walkingDurationMinutes
        automobileDurationMinutes = candidate.result.automobileDurationMinutes
    }
}
