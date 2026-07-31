import Foundation

struct GuidedComposerConnectorOption: Equatable {
    let displayText: String
    let connector: ComposerConnector
    let slot: ComposerSlot
}

enum GuidedComposerGrammar {
    private struct ClauseState {
        let previousRole: ComposerValueRole?
        let hasPeopleClause: Bool
        let hasVisitLocation: Bool
        let hasOrigin: Bool
        let hasDestination: Bool
        let hasExplicitStart: Bool
        let hasExplicitEnd: Bool
        let hasDuration: Bool

        /// An explicit pair or a duration anchored to either boundary already
        /// determines the complete interval. Derived draft times must not be
        /// mistaken for additional explicit clauses when deciding grammar.
        var hasResolvedInterval: Bool {
            (hasExplicitStart && hasExplicitEnd)
                || (hasDuration && (hasExplicitStart || hasExplicitEnd))
        }

        var needsStartBoundary: Bool {
            !hasExplicitStart && !hasResolvedInterval
        }

        var needsEndBoundary: Bool {
            !hasExplicitEnd && !hasResolvedInterval
        }

        init(tokens: [ComposerToken]) {
            previousRole = tokens.reversed().first {
                if case .connector = $0.value { return false }
                return true
            }?.role

            var visitLocation = false
            var origin = false
            var destination = false
            var explicitStart = false
            var explicitEnd = false
            var duration = false
            var peopleClause = false
            for token in tokens {
                switch token.value {
                case .location(_, .visit):
                    visitLocation = true
                case .location(_, .origin):
                    origin = true
                case .location(_, .destination):
                    destination = true
                case .time(_, .start):
                    explicitStart = true
                case .time(_, .end):
                    explicitEnd = true
                case .duration:
                    duration = true
                case .connector(.with):
                    peopleClause = GuidedComposerNormalization.text(
                        token.displayText
                    ) == ComposerConnector.with.rawValue || peopleClause
                case .leading, .connector, .person:
                    break
                }
            }
            hasVisitLocation = visitLocation
            hasOrigin = origin
            hasDestination = destination
            hasExplicitStart = explicitStart
            hasExplicitEnd = explicitEnd
            hasDuration = duration
            hasPeopleClause = peopleClause
        }
    }

    static func legalConnectors(
        entryKind: ComposerEntryKind,
        tokens: [ComposerToken]
    ) -> [(connector: ComposerConnector, slot: ComposerSlot)] {
        let state = ClauseState(tokens: tokens)

        switch entryKind {
        case .placeVisit:
            var result: [(ComposerConnector, ComposerSlot)] = []
            if !state.hasVisitLocation {
                result.append((.at, .location(.visit)))
            } else if state.needsStartBoundary {
                result.append((.at, .time(.start)))
            }
            if state.needsStartBoundary {
                result.append((.from, .time(.start)))
                result.append((.since, .time(.start)))
            }
            if state.needsEndBoundary {
                result.append((.to, .time(.end)))
                result.append((.until, .time(.end)))
            }
            if !state.hasDuration,
               !(state.hasExplicitStart && state.hasExplicitEnd),
               state.hasVisitLocation
                   || state.hasExplicitStart
                   || state.hasExplicitEnd {
                result.append((.forDuration, .duration))
            }
            if !state.hasPeopleClause {
                result.append((.with, .person))
            }
            return deduplicated(result)

        case .transit:
            var result: [(ComposerConnector, ComposerSlot)] = []
            if !state.hasOrigin {
                result.append((.from, .location(.origin)))
            } else if state.hasDestination, state.needsStartBoundary {
                result.append((.from, .time(.start)))
            }
            if !state.hasDestination {
                result.append((.to, .location(.destination)))
            } else if state.hasOrigin, state.needsEndBoundary {
                result.append((.to, .time(.end)))
            }
            if state.previousRole == .location(.origin),
               state.needsStartBoundary {
                result.append((.at, .time(.start)))
            }
            if state.previousRole == .location(.destination),
               state.needsEndBoundary {
                result.append((.at, .time(.end)))
            }
            if !state.hasDuration,
               state.hasOrigin,
               state.hasDestination,
               state.hasExplicitStart != state.hasExplicitEnd {
                result.append((.forDuration, .duration))
            }
            if !state.hasPeopleClause {
                result.append((.with, .person))
            }
            return deduplicated(result)
        }
    }

    private static func deduplicated(
        _ values: [(ComposerConnector, ComposerSlot)]
    ) -> [(connector: ComposerConnector, slot: ComposerSlot)] {
        var seen: Set<String> = []
        return values.filter {
            seen.insert("\($0.0.rawValue)-\($0.1)").inserted
        }
    }

    static func replacementOptions(
        entryKind: ComposerEntryKind,
        tokens: [ComposerToken],
        connectorIndex: Int,
        currentDisplayText: String
    ) -> [GuidedComposerConnectorOption] {
        guard tokens.indices.contains(connectorIndex),
              case .connector = tokens[connectorIndex].value,
              let nextRole = tokens[tokens.index(after: connectorIndex)...]
                .first(where: { $0.role != .connector })?.role else {
            return []
        }

        let options: [GuidedComposerConnectorOption]
        if nextRole == .person {
            if GuidedComposerNormalization.text(currentDisplayText)
                == ComposerConnector.with.rawValue {
                options = [option(.with, slot: .person)]
            } else {
                options = [",", "and", "&"].map {
                    GuidedComposerConnectorOption(
                        displayText: $0,
                        connector: .with,
                        slot: .person
                    )
                }
            }
        } else {
            let prefix = Array(tokens[..<connectorIndex])
            options = legalConnectors(
                entryKind: entryKind,
                tokens: prefix
            ).compactMap { candidate in
                guard candidate.slot == nextRole.slot else { return nil }
                return option(candidate.connector, slot: candidate.slot)
            }
        }

        let normalizedCurrent = GuidedComposerNormalization.text(
            currentDisplayText
        )
        return options.sorted {
            let leftIsCurrent = GuidedComposerNormalization.text(
                $0.displayText
            ) == normalizedCurrent
            let rightIsCurrent = GuidedComposerNormalization.text(
                $1.displayText
            ) == normalizedCurrent
            if leftIsCurrent != rightIsCurrent {
                return leftIsCurrent
            }
            return $0.displayText.localizedStandardCompare($1.displayText)
                == .orderedAscending
        }
    }

    private static func option(
        _ connector: ComposerConnector,
        slot: ComposerSlot
    ) -> GuidedComposerConnectorOption {
        GuidedComposerConnectorOption(
            displayText: connector.rawValue,
            connector: connector,
            slot: slot
        )
    }
}
