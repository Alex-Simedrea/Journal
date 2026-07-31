import Foundation

struct GuidedComposerConnectorOption: Equatable {
    let displayText: String
    let connector: ComposerConnector
    let slot: ComposerSlot
}

enum GuidedComposerGrammar {
    static func legalConnectors(
        entryKind: ComposerEntryKind,
        tokens: [ComposerToken]
    ) -> [(connector: ComposerConnector, slot: ComposerSlot)] {
        let draft = ComposerDraft(tokens: tokens)
        let previousRole = tokens.reversed().first {
            if case .connector = $0.value { return false }
            return true
        }?.role
        let hasPeopleClause = tokens.contains { token in
            guard case .connector(.with) = token.value else {
                return false
            }
            return GuidedComposerNormalization.text(token.displayText)
                == ComposerConnector.with.rawValue
        }

        switch entryKind {
        case .placeVisit:
            var result: [(ComposerConnector, ComposerSlot)] = []
            let needsStart = draft.startTime == nil
            let needsEnd = draft.endTime == nil
            if draft.location(.visit) == nil {
                result.append((.at, .location(.visit)))
            } else if needsStart {
                result.append((.at, .time(.start)))
            }
            if needsStart {
                result.append((.from, .time(.start)))
                result.append((.since, .time(.start)))
            }
            if needsEnd {
                result.append((.to, .time(.end)))
                result.append((.until, .time(.end)))
            }
            if draft.duration == nil,
               draft.location(.visit) != nil,
               needsStart || needsEnd {
                result.append((.forDuration, .duration))
            }
            if !hasPeopleClause {
                result.append((.with, .person))
            }
            return deduplicated(result)

        case .transit:
            var result: [(ComposerConnector, ComposerSlot)] = []
            let hasOrigin = draft.location(.origin) != nil
            let hasDestination = draft.location(.destination) != nil
            let needsStart = draft.startTime == nil
            let needsEnd = draft.endTime == nil
            if !hasOrigin {
                result.append((.from, .location(.origin)))
            } else if hasDestination, needsStart {
                result.append((.from, .time(.start)))
            }
            if !hasDestination {
                result.append((.to, .location(.destination)))
            } else if hasOrigin, needsEnd {
                result.append((.to, .time(.end)))
            }
            if previousRole == .location(.origin), needsStart {
                result.append((.at, .time(.start)))
            }
            if previousRole == .location(.destination), needsEnd {
                result.append((.at, .time(.end)))
            }
            if draft.duration == nil,
               hasOrigin,
               hasDestination,
               needsStart != needsEnd {
                result.append((.forDuration, .duration))
            }
            if !hasPeopleClause {
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
        previousRole: ComposerValueRole?,
        nextRole: ComposerValueRole,
        currentDisplayText: String
    ) -> [GuidedComposerConnectorOption] {
        let options: [GuidedComposerConnectorOption]
        switch nextRole {
        case .location(.visit):
            options = [option(.at, slot: .location(.visit))]
        case .location(.origin):
            options = [option(.from, slot: .location(.origin))]
        case .location(.destination):
            options = [option(.to, slot: .location(.destination))]
        case .time(.start):
            switch entryKind {
            case .placeVisit:
                options = [
                    option(.at, slot: .time(.start)),
                    option(.from, slot: .time(.start)),
                    option(.since, slot: .time(.start)),
                ]
            case .transit:
                options = [
                    option(.from, slot: .time(.start)),
                ] + (
                    previousRole == .location(.origin)
                        ? [option(.at, slot: .time(.start))]
                        : []
                )
            }
        case .time(.end):
            switch entryKind {
            case .placeVisit:
                options = [
                    option(.to, slot: .time(.end)),
                    option(.until, slot: .time(.end)),
                ]
            case .transit:
                options = [
                    option(.to, slot: .time(.end)),
                ] + (
                    previousRole == .location(.destination)
                        ? [option(.at, slot: .time(.end))]
                        : []
                )
            }
        case .duration:
            options = [option(.forDuration, slot: .duration)]
        case .person:
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
        case .leading, .connector:
            options = []
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
