import Foundation

enum GuidedComposerSuggestionDeduplicator {
    static func deduplicated(
        _ suggestions: [ComposerSuggestion]
    ) -> [ComposerSuggestion] {
        var result: [ComposerSuggestion] = []
        var seenIDs: Set<String> = []
        var seenActions: Set<String> = []

        for suggestion in suggestions.sorted(by: { $0.score > $1.score }) {
            guard seenIDs.insert(suggestion.id).inserted,
                  seenActions.insert(actionKey(for: suggestion)).inserted else {
                continue
            }
            result.append(suggestion)
        }
        return result
    }

    private static func actionKey(for suggestion: ComposerSuggestion) -> String {
        switch suggestion.kind {
        case .addPerson(let name):
            return "add-person:\(GuidedComposerNormalization.text(name))"
        case .semanticSplit(let bindings, let nextSlot):
            let values = bindings.map {
                "\($0.range.lowerBound)-\($0.range.upperBound):"
                    + tokenKey(for: $0.token)
            }.joined(separator: "|")
            return "split:\(values):\(nextSlot)"
        case .value(let tokens, let nextSlot),
             .macro(let tokens, let nextSlot):
            return tokens.map { tokenKey(for: $0) }.joined(separator: "|")
                + ":\(nextSlot)"
        }
    }

    private static func tokenKey(for token: ComposerToken) -> String {
        switch token.value {
        case .leading(.transit(let canonicalName)):
            return "type:\(GuidedComposerNormalization.text(canonicalName))"
        case .leading(.placeVisit(let description)):
            return "visit:"
                + GuidedComposerNormalization.text(description ?? "stay")
        case .connector(let connector):
            return "connector:\(connector.rawValue):"
                + GuidedComposerNormalization.text(token.displayText)
        case .location(let location, let role):
            let identity: String
            if let savedPlaceID = location.savedPlaceID {
                identity = "saved-\(savedPlaceID.uuidString)"
            } else {
                let latitude = Int(
                    (location.location.latitude * 100_000).rounded()
                )
                let longitude = Int(
                    (location.location.longitude * 100_000).rounded()
                )
                identity = [
                    GuidedComposerNormalization.text(location.displayName),
                    String(latitude),
                    String(longitude),
                ].joined(separator: ":")
            }
            return "location:\(role.rawValue):\(identity)"
        case .time(let time, let role):
            return "time:\(role.rawValue):"
                + "\(Int(time.date.timeIntervalSince1970.rounded())):"
                + time.timeZoneIdentifier
        case .duration(let duration):
            return "duration:\(Int(duration.interval.rounded()))"
        case .person(let person):
            return "person:\(person.id.uuidString)"
        }
    }
}
