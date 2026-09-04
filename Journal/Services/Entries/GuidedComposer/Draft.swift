import Foundation

struct ComposerDraft: Equatable, Sendable {
    var tokens: [ComposerToken] = []

    var entryKind: ComposerEntryKind? {
        tokens.compactMap {
            guard case .leading(let value) = $0.value else { return nil }
            return value
        }.first
    }

    func location(_ role: ComposerLocationRole) -> ComposerLocationCandidate? {
        tokens.reversed().compactMap {
            guard case .location(let location, let tokenRole) = $0.value,
                  tokenRole == role else {
                return nil
            }
            return location
        }.first
    }

    func time(_ role: ComposerTimeRole) -> ComposerTimeValue? {
        tokens.reversed().compactMap {
            guard case .time(let time, let tokenRole) = $0.value,
                  tokenRole == role else {
                return nil
            }
            return time
        }.first
    }

    var duration: TimeInterval? {
        tokens.reversed().compactMap {
            guard case .duration(let value) = $0.value else { return nil }
            return value.interval
        }.first
    }

    var durationSource: DurationSource {
        if let durationValue = tokens.reversed().compactMap({
            token -> ComposerDurationValue? in
            guard case .duration(let value) = token.value else { return nil }
            return value
        }).first {
            return durationValue.source
        }
        return [startTime, endTime]
            .compactMap { $0?.durationSource }
            .first ?? .unresolved
    }

    var people: [ComposerPersonCandidate] {
        var seen: Set<UUID> = []
        return tokens.compactMap {
            guard case .person(let person) = $0.value,
                  seen.insert(person.id).inserted else {
                return nil
            }
            return person
        }
    }

    var startTime: ComposerTimeValue? {
        if let value = time(.start) { return value }
        guard let end = time(.end), let duration else { return nil }
        return ComposerTimeValue(
            date: end.date.addingTimeInterval(-duration),
            timeZoneIdentifier: location(.origin)?
                .location.timeZoneIdentifier
                ?? location(.visit)?.location.timeZoneIdentifier
                ?? end.timeZoneIdentifier,
            source: end.source
        )
    }

    var endTime: ComposerTimeValue? {
        if let value = time(.end) {
            guard let start = time(.start),
                  value.date <= start.date,
                  value.allowsOvernightRollover else {
                return value
            }
            let zone = TimeZone(
                identifier: value.timeZoneIdentifier
            ) ?? .current
            return ComposerTimeValue(
                date: GuidedComposerTimeParser.rolledEndIfNeeded(
                    value.date,
                    after: start.date,
                    hadExplicitDate: false,
                    timeZone: zone
                ),
                timeZoneIdentifier: value.timeZoneIdentifier,
                source: value.source,
                durationSource: value.durationSource,
                allowsOvernightRollover: true
            )
        }
        guard let start = time(.start), let duration else { return nil }
        return ComposerTimeValue(
            date: start.date.addingTimeInterval(duration),
            timeZoneIdentifier: location(.destination)?
                .location.timeZoneIdentifier
                ?? location(.visit)?.location.timeZoneIdentifier
                ?? start.timeZoneIdentifier,
            source: start.source
        )
    }

    var timeConfidence: TimeConfidence {
        let sources = [startTime?.source, endTime?.source].compactMap { $0 }
        if sources.contains(.nearOrigin) { return .inferredNearOrigin }
        if sources.contains(.nearDestination) { return .inferredNearDestination }
        if sources.contains(.history) { return .inferredFromHistory }
        return .explicit
    }

    var canSubmit: Bool {
        guard let entryKind, let start = startTime?.date,
              let end = endTime?.date, end > start else {
            return false
        }
        switch entryKind {
        case .placeVisit:
            return location(.visit) != nil
        case .transit:
            guard let origin = location(.origin),
                  let destination = location(.destination) else {
                return false
            }
            return !GuidedComposerLocationMatcher.sameLocation(
                origin,
                destination
            )
        }
    }

    var rawSentence: String {
        tokens.map(\.displayText)
            .joined(separator: " ")
            .replacingOccurrences(of: " ,", with: ",")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ComposerSuggestionKind: Equatable, Sendable {
    case value(tokens: [ComposerToken], nextSlot: ComposerSlot)
    case macro(tokens: [ComposerToken], nextSlot: ComposerSlot)
    case addPerson(name: String)
    case semanticSplit(
        bindings: [ComposerSemanticBinding],
        nextSlot: ComposerSlot
    )
}

struct ComposerSuggestion: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let kind: ComposerSuggestionKind
    let score: Int

    /// Timeline-derived endpoints are linked automatically when the completed
    /// entry lands on that boundary. The badge is informational; accepting the
    /// suggestion is not what creates the link.
    var referencesTimelineBoundary: Bool {
        suggestionTokens.contains { token in
            guard case .location(let candidate, _) = token.value else {
                return false
            }
            return candidate.source == .timeline
        }
    }

    private var suggestionTokens: [ComposerToken] {
        switch kind {
        case .value(let tokens, _), .macro(let tokens, _):
            tokens
        case .semanticSplit(let bindings, _):
            bindings.map(\.token)
        case .addPerson:
            []
        }
    }
}
