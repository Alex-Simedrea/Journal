import Foundation

struct GuidedComposerSemanticParser {
    struct Input {
        let text: String
        let selection: Range<Int>
        let bindings: [ComposerSemanticBinding]
        let transitTypes: [ComposerTransitTypeCandidate]
        let locations: [ComposerLocationCandidate]
        let people: [ComposerPersonCandidate]
        let selectedDay: TimelineDayKey
    }

    private struct ResolvedValue {
        let token: ComposerToken
        let range: Range<Int>
        let resolution: ComposerResolutionState
        let hasLongerMatches: Bool
    }

    static func parse(_ input: Input) -> ComposerParseSnapshot {
        Parser(input: input).parse()
    }

    private struct Parser {
        let input: Input
        let source: IntegerIndexedText
        let segments: [ComposerTextSegment]
        let textLength: Int

        init(input: Input) {
            self.input = input
            let source = IntegerIndexedText(input.text)
            self.source = source
            segments = GuidedComposerLexer.segments(in: input.text)
            textLength = source.count
        }

        func parse() -> ComposerParseSnapshot {
            guard let first = segments.first else {
                return snapshot(
                    spans: [],
                    clauses: [
                        ComposerParsedClauseRange(
                            range: 0..<0,
                            slot: .leading
                        ),
                    ],
                    fallbackRange: 0..<0,
                    fallbackSlot: .leading,
                    fallbackQuery: "",
                    continuation: nil,
                    alternatives: [],
                    syntaxValid: false
                )
            }

            var spans: [ComposerSemanticSpan] = []
            var clauses: [ComposerParsedClauseRange] = []
            var alternatives: [ComposerParseAlternative] = []
            let leading = resolveLeading(startingAt: first.range.lowerBound)
            let leadingInteractionRange = first.range.lowerBound..<textLength

            guard let leading else {
                clauses.append(
                    ComposerParsedClauseRange(
                        range: leadingInteractionRange,
                        slot: .leading
                    )
                )
                return snapshot(
                    spans: [],
                    clauses: clauses,
                    fallbackRange: trimmed(leadingInteractionRange),
                    fallbackSlot: .leading,
                    fallbackQuery: substring(trimmed(leadingInteractionRange)),
                    continuation: nil,
                    alternatives: [],
                    syntaxValid: false
                )
            }

            spans.append(
                ComposerSemanticSpan(
                    token: leading.token,
                    range: leading.range,
                    resolution: leading.resolution
                )
            )
            clauses.append(
                ComposerParsedClauseRange(
                    range: leading.range,
                    slot: .leading
                )
            )

            guard case .leading(let entryKind) = leading.token.value else {
                return invalidSnapshot(
                    spans: spans,
                    clauses: clauses,
                    range: leading.range,
                    slot: .leading
                )
            }

            var position = skipWhitespace(from: leading.range.upperBound)
            var fallbackRange = leading.range
            var fallbackSlot: ComposerSlot = .leading
            var fallbackQuery = substring(leading.range)
            var continuation: ComposerContinuationContext?
            let syntaxValid = true

            if position >= textLength {
                let hasTrailingSpace = leading.range.upperBound < textLength
                if hasTrailingSpace {
                    fallbackRange = position..<position
                    fallbackSlot = .connector
                    fallbackQuery = ""
                    if leading.hasLongerMatches {
                        continuation = ComposerContinuationContext(
                            slot: .leading,
                            query: substring(leading.range),
                            range: leading.range
                        )
                    }
                }
                return snapshot(
                    spans: spans,
                    clauses: clauses,
                    fallbackRange: fallbackRange,
                    fallbackSlot: fallbackSlot,
                    fallbackQuery: fallbackQuery,
                    continuation: continuation,
                    alternatives: alternatives,
                    syntaxValid: syntaxValid
                )
            }

            while position < textLength {
                guard let connectorSegment = segment(startingAt: position),
                      let syntax = clauseSyntax(
                          connectorSegment,
                          entryKind: entryKind,
                          tokens: spans.map(\.token),
                          allowsPersonSeparator:
                              lastValueRole(in: spans) == .person
                      ),
                      syntaxIsComplete(syntax) else {
                    if shouldResumeLeadingQuery(
                        leading: leading,
                        at: position,
                        entryKind: entryKind,
                        parsedTokens: spans.map(\.token)
                    ) {
                        let range = trimmed(
                            leading.range.lowerBound..<textLength
                        )
                        return snapshot(
                            spans: [],
                            clauses: [
                                ComposerParsedClauseRange(
                                    range: range,
                                    slot: .leading
                                ),
                            ],
                            fallbackRange: range,
                            fallbackSlot: .leading,
                            fallbackQuery: substring(range),
                            continuation: nil,
                            alternatives: [],
                            syntaxValid: false
                        )
                    }
                    let unresolved = trimmed(position..<textLength)
                    clauses.append(
                        ComposerParsedClauseRange(
                            range: position..<textLength,
                            slot: .connector
                        )
                    )
                    return snapshot(
                        spans: spans,
                        clauses: clauses,
                        fallbackRange: unresolved,
                        fallbackSlot: .connector,
                        fallbackQuery: substring(unresolved),
                        continuation: continuation,
                        alternatives: alternatives,
                        syntaxValid: false
                    )
                }

                if leading.resolution == .softResolved,
                   leading.hasLongerMatches,
                   connectorSegment.range.lowerBound
                        == skipWhitespace(from: leading.range.upperBound),
                   !hasCommittedBoundary(
                        valueRange: leading.range,
                        connectorRange: connectorSegment.range
                   ) {
                        alternatives.append(
                            splitAlternative(
                                value: leading,
                                syntax: syntax
                            )
                        )
                    let unresolved = trimmed(
                        leading.range.lowerBound..<textLength
                    )
                    return snapshot(
                        spans: spans,
                        clauses: clauses,
                        fallbackRange: unresolved,
                        fallbackSlot: .leading,
                        fallbackQuery: substring(unresolved),
                        continuation: nil,
                        alternatives: alternatives,
                        syntaxValid: false
                    )
                }

                let connectorResolution: ComposerResolutionState =
                    binding(
                        exactly: connectorSegment.range,
                        role: .connector
                    ) == nil ? .softResolved : .committed
                let connectorToken = ComposerToken(
                    displayText: connectorSegment.text,
                    value: .connector(syntax.connector)
                )
                spans.append(
                    ComposerSemanticSpan(
                        token: connectorToken,
                        range: connectorSegment.range,
                        resolution: connectorResolution
                    )
                )

                let contentStart = skipWhitespace(
                    from: connectorSegment.range.upperBound
                )
                let clauseStart = connectorSegment.range.upperBound
                guard contentStart < textLength else {
                    let range = clauseStart..<textLength
                    clauses.append(
                        ComposerParsedClauseRange(
                            range: range,
                            slot: syntax.nextSlot
                        )
                    )
                    return snapshot(
                        spans: spans,
                        clauses: clauses,
                        fallbackRange: contentStart..<contentStart,
                        fallbackSlot: syntax.nextSlot,
                        fallbackQuery: "",
                        continuation: nil,
                        alternatives: alternatives,
                        syntaxValid: false
                    )
                }

                let boundaryResult = findBoundary(
                    from: contentStart,
                    slot: syntax.nextSlot,
                    entryKind: entryKind,
                    priorSpans: spans
                )

                switch boundaryResult {
                case .resolved(let value, let nextSyntax):
                    spans.append(
                        ComposerSemanticSpan(
                            token: value.token,
                            range: value.range,
                            resolution: value.resolution
                        )
                    )
                    clauses.append(
                        ComposerParsedClauseRange(
                            range: clauseStart..<nextSyntax.range.lowerBound,
                            slot: syntax.nextSlot
                        )
                    )
                    let nextConnectorIsComplete = syntaxIsComplete(nextSyntax)
                    if !nextConnectorIsComplete {
                        alternatives.append(
                            splitAlternative(
                                value: value,
                                syntax: nextSyntax,
                                compactTitle: true
                            )
                        )
                        let unresolved = trimmed(contentStart..<textLength)
                        return snapshot(
                            spans: spans,
                            clauses: clauses,
                            fallbackRange: unresolved,
                            fallbackSlot: syntax.nextSlot,
                            fallbackQuery: substring(unresolved),
                            continuation: nil,
                            alternatives: alternatives,
                            syntaxValid: false
                        )
                    }
                    if value.resolution == .softResolved,
                       value.hasLongerMatches,
                       !hasCommittedBoundary(
                           valueRange: value.range,
                           connectorRange: nextSyntax.range
                       ) {
                        alternatives.append(
                            splitAlternative(
                                value: value,
                                syntax: nextSyntax
                            )
                        )
                        let unresolved = trimmed(contentStart..<textLength)
                        return snapshot(
                            spans: spans,
                            clauses: clauses,
                            fallbackRange: unresolved,
                            fallbackSlot: syntax.nextSlot,
                            fallbackQuery: substring(unresolved),
                            continuation: nil,
                            alternatives: alternatives,
                            syntaxValid: false
                        )
                    }
                    position = nextSyntax.range.lowerBound

                case .terminal(let value, let interactionRange):
                    clauses.append(
                        ComposerParsedClauseRange(
                            range: clauseStart..<textLength,
                            slot: syntax.nextSlot
                        )
                    )
                    guard let value else {
                        let unresolved = trimmed(interactionRange)
                        return snapshot(
                            spans: spans,
                            clauses: clauses,
                            fallbackRange: unresolved,
                            fallbackSlot: syntax.nextSlot,
                            fallbackQuery: substring(unresolved),
                            continuation: nil,
                            alternatives: alternatives,
                            syntaxValid: false
                        )
                    }
                    spans.append(
                        ComposerSemanticSpan(
                            token: value.token,
                            range: value.range,
                            resolution: value.resolution
                        )
                    )
                    let afterValue = skipWhitespace(
                        from: value.range.upperBound
                    )
                    if afterValue >= textLength,
                       value.range.upperBound < textLength {
                        fallbackRange = textLength..<textLength
                        fallbackSlot = syntax.nextSlot == .person
                            ? .person
                            : .connector
                        fallbackQuery = ""
                        if value.hasLongerMatches {
                            continuation = ComposerContinuationContext(
                                slot: syntax.nextSlot,
                                query: substring(value.range),
                                range: value.range
                            )
                        }
                    } else {
                        fallbackRange = value.range
                        fallbackSlot = syntax.nextSlot
                        fallbackQuery = substring(value.range)
                    }
                    position = textLength
                }
            }

            return snapshot(
                spans: spans,
                clauses: clauses,
                fallbackRange: fallbackRange,
                fallbackSlot: fallbackSlot,
                fallbackQuery: fallbackQuery,
                continuation: continuation,
                alternatives: alternatives,
                syntaxValid: syntaxValid
                    && nonWhitespaceIsCovered(by: spans.map(\.range))
            )
        }

        private enum BoundaryResult {
            case resolved(
                value: ResolvedValue,
                nextSyntax: ClauseSyntax
            )
            case terminal(value: ResolvedValue?, interactionRange: Range<Int>)
        }

        private struct ClauseSyntax {
            let connector: ComposerConnector
            let range: Range<Int>
            let nextSlot: ComposerSlot
            let isPersonSeparator: Bool
        }

        private func findBoundary(
            from contentStart: Int,
            slot: ComposerSlot,
            entryKind: ComposerEntryKind,
            priorSpans: [ComposerSemanticSpan]
        ) -> BoundaryResult {
            if let committed = input.bindings.filter({
                $0.range.lowerBound == contentStart
                    && $0.token.role.slot == slot
                    && bindingStillMatches($0)
            }).max(by: {
                $0.range.upperBound < $1.range.upperBound
            }) {
                let value = ResolvedValue(
                    token: resolveBindingToken(committed),
                    range: committed.range,
                    resolution: .committed,
                    hasLongerMatches: false
                )
                let nextOffset = skipWhitespace(
                    from: committed.range.upperBound
                )
                guard nextOffset < textLength else {
                    return .terminal(
                        value: value,
                        interactionRange: contentStart..<textLength
                    )
                }
                if let connectorSegment = segment(startingAt: nextOffset),
                   let syntax = clauseSyntax(
                       connectorSegment,
                       entryKind: entryKind,
                       tokens: priorSpans.map(\.token) + [value.token],
                       allowsPersonSeparator: slot == .person
                   ) {
                    return .resolved(
                        value: value,
                        nextSyntax: syntax
                    )
                }
                return .terminal(
                    value: value,
                    interactionRange: contentStart..<textLength
                )
            }

            let candidates = segments.filter {
                $0.range.lowerBound > contentStart
                    && (
                        connector(for: $0.text) != nil
                            || slot == .person && isPersonSeparator($0.text)
                    )
            }
            for candidate in candidates {
                let valueRange = trimmed(
                    contentStart..<candidate.range.lowerBound
                )
                guard !valueRange.isEmpty,
                      let value = resolveValue(
                          range: valueRange,
                          slot: slot,
                          parsedTokens: priorSpans.map(\.token)
                      ) else {
                    continue
                }
                let tokens = priorSpans.map(\.token) + [value.token]
                guard let syntax = clauseSyntax(
                    candidate,
                    entryKind: entryKind,
                    tokens: tokens,
                    allowsPersonSeparator: slot == .person
                ) else {
                    continue
                }
                return .resolved(
                    value: value,
                    nextSyntax: syntax
                )
            }

            let interactionRange = contentStart..<textLength
            let valueRange = trimmed(interactionRange)
            let value = valueRange.isEmpty ? nil : resolveValue(
                range: valueRange,
                slot: slot,
                parsedTokens: priorSpans.map(\.token)
            )
            return .terminal(value: value, interactionRange: interactionRange)
        }

        private func resolveLeading(startingAt start: Int) -> ResolvedValue? {
            if let binding = input.bindings.first(where: {
                $0.range.lowerBound == start
                    && $0.token.role == .leading
                    && bindingStillMatches($0)
            }) {
                return ResolvedValue(
                    token: token(
                        from: binding.token,
                        displayText: substring(binding.range)
                    ),
                    range: binding.range,
                    resolution: .committed,
                    hasLongerMatches: false
                )
            }

            var matches: [(range: Range<Int>, kind: ComposerEntryKind)] = []
            for endSegment in segments.indices {
                let range = start..<segments[endSegment].range.upperBound
                let query = normalized(substring(range))
                if query == "stay" {
                    matches.append((range, .placeVisit(description: nil)))
                }
                for type in input.transitTypes
                where ([type.canonicalName] + type.aliases).contains(
                    where: { normalized($0) == query }
                ) {
                    matches.append(
                        (range, .transit(canonicalName: type.canonicalName))
                    )
                }
            }
            let identities = Dictionary(grouping: matches) {
                "\($0.kind)"
            }.compactMap(\.value.first)
            guard let best = identities.max(by: {
                $0.range.count < $1.range.count
            }) else {
                return nil
            }
            let sameLength = identities.filter {
                $0.range == best.range
            }
            guard sameLength.count == 1 else { return nil }
            let query = substring(best.range)
            return ResolvedValue(
                token: ComposerToken(
                    displayText: query,
                    value: .leading(best.kind)
                ),
                range: best.range,
                resolution: .softResolved,
                hasLongerMatches: hasLongerLeadingMatch(query)
            )
        }

        private func shouldResumeLeadingQuery(
            leading: ResolvedValue,
            at position: Int,
            entryKind: ComposerEntryKind,
            parsedTokens: [ComposerToken]
        ) -> Bool {
            guard leading.resolution == .softResolved,
                  position == skipWhitespace(from: leading.range.upperBound),
                  let segment = segment(startingAt: position) else {
                return false
            }
            let legalConnectorNames = GuidedComposerGrammar.legalConnectors(
                entryKind: entryKind,
                tokens: parsedTokens
            ).map(\.connector.rawValue)
            return GuidedComposerRanking.textScore(
                query: segment.text,
                candidates: legalConnectorNames
            ) == nil
        }

        private func resolveValue(
            range: Range<Int>,
            slot: ComposerSlot,
            parsedTokens: [ComposerToken]
        ) -> ResolvedValue? {
            if let binding = input.bindings.first(where: {
                $0.range == range
                    && $0.token.role.slot == slot
                    && bindingStillMatches($0)
            }) {
                return ResolvedValue(
                    token: token(
                        from: binding.token,
                        displayText: substring(range)
                    ),
                    range: range,
                    resolution: .committed,
                    hasLongerMatches: false
                )
            }

            let query = substring(range)
            let normalizedQuery = normalized(query)
            guard !normalizedQuery.isEmpty else { return nil }

            switch slot {
            case .location(let role):
                let matches = input.locations.filter { candidate in
                    candidate.allSearchTerms.contains {
                        normalized($0) == normalizedQuery
                    }
                }
                guard matches.count == 1, let candidate = matches.first else {
                    return nil
                }
                return ResolvedValue(
                    token: ComposerToken(
                        displayText: query,
                        value: .location(candidate, role)
                    ),
                    range: range,
                    resolution: .softResolved,
                    hasLongerMatches: input.locations.contains {
                        $0.id != candidate.id
                            && $0.allSearchTerms.contains {
                                isLonger($0, than: query)
                            }
                    }
                )

            case .person:
                let selectedIDs = Set(parsedTokens.compactMap {
                    token -> UUID? in
                    guard case .person(let person) = token.value else {
                        return nil
                    }
                    return person.id
                })
                let matches = input.people.filter {
                    !selectedIDs.contains($0.id)
                        && ([$0.name] + $0.aliases).contains {
                            normalized($0) == normalizedQuery
                        }
                }
                guard matches.count == 1, let person = matches.first else {
                    return nil
                }
                return ResolvedValue(
                    token: ComposerToken(
                        displayText: query,
                        value: .person(person)
                    ),
                    range: range,
                    resolution: .softResolved,
                    hasLongerMatches: input.people.contains {
                        $0.id != person.id
                            && !selectedIDs.contains($0.id)
                            && ([$0.name] + $0.aliases).contains {
                                isLonger($0, than: query)
                            }
                    }
                )

            case .time(let role):
                let zone = timeZone(for: role, parsedTokens: parsedTokens)
                guard var date = GuidedComposerTimeParser.parseTime(
                    query,
                    role: role,
                    selectedDay: input.selectedDay,
                    timeZone: zone
                ) else {
                    return nil
                }
                if role == .end,
                   let start = parsedTokens.reversed().compactMap({
                       token -> Date? in
                       guard case .time(let value, .start) = token.value else {
                           return nil
                       }
                       return value.date
                   }).first {
                    date = GuidedComposerTimeParser.rolledEndIfNeeded(
                        date,
                        after: start,
                        hadExplicitDate: !GuidedComposerTimeParser
                            .isUnqualifiedClock(query),
                        timeZone: zone
                    )
                }
                return ResolvedValue(
                    token: ComposerTokenFactory.explicitTime(
                        date: date,
                        timeZone: zone,
                        role: role,
                        displayText: query,
                        allowsOvernightRollover:
                            role == .end
                            && GuidedComposerTimeParser
                                .isUnqualifiedClock(query)
                    ),
                    range: range,
                    resolution: .softResolved,
                    hasLongerMatches: false
                )

            case .duration:
                guard let interval = GuidedComposerTimeParser.parseDuration(
                    query
                ) else {
                    return nil
                }
                return ResolvedValue(
                    token: ComposerToken(
                        displayText: query,
                        value: .duration(
                            ComposerDurationValue(
                                interval: interval,
                                source: .manualOverride
                            )
                        )
                    ),
                    range: range,
                    resolution: .softResolved,
                    hasLongerMatches: false
                )

            case .leading, .connector:
                return nil
            }
        }

        private func slot(
            after connector: ComposerConnector,
            entryKind: ComposerEntryKind,
            tokens: [ComposerToken]
        ) -> ComposerSlot? {
            GuidedComposerGrammar.legalConnectors(
                entryKind: entryKind,
                tokens: tokens
            ).first {
                $0.connector == connector
            }?.slot
        }

        private func clauseSyntax(
            _ segment: ComposerTextSegment,
            entryKind: ComposerEntryKind,
            tokens: [ComposerToken],
            allowsPersonSeparator: Bool
        ) -> ClauseSyntax? {
            if allowsPersonSeparator, isPersonSeparator(segment.text) {
                return ClauseSyntax(
                    connector: .with,
                    range: segment.range,
                    nextSlot: .person,
                    isPersonSeparator: true
                )
            }
            guard let connector = connector(for: segment.text),
                  let nextSlot = slot(
                      after: connector,
                      entryKind: entryKind,
                      tokens: tokens
                  ) else {
                return nil
            }
            return ClauseSyntax(
                connector: connector,
                range: segment.range,
                nextSlot: nextSlot,
                isPersonSeparator: false
            )
        }

        private func lastValueRole(
            in spans: [ComposerSemanticSpan]
        ) -> ComposerValueRole? {
            spans.reversed().first {
                $0.token.role != .connector
            }?.token.role
        }

        private func splitAlternative(
            value: ResolvedValue,
            syntax: ClauseSyntax,
            compactTitle: Bool = false
        ) -> ComposerParseAlternative {
            let valueBinding = ComposerSemanticBinding(
                token: value.token,
                range: value.range
            )
            let connectorToken = ComposerToken(
                displayText: substring(syntax.range),
                value: .connector(syntax.connector)
            )
            let connectorBinding = ComposerSemanticBinding(
                token: connectorToken,
                range: syntax.range
            )
            let syntaxText = substring(syntax.range)
            let splitSubtitle = syntax.isPersonSeparator
                ? String(
                    localized:
                        "Use “\(syntaxText)” as person separator"
                )
                : String(
                    localized:
                        "Use “\(syntaxText)” as connector"
                )
            return ComposerParseAlternative(
                id: "split-\(value.range.lowerBound)-\(syntax.range.lowerBound)",
                title: compactTitle
                    ? syntaxText
                    : "\(substring(value.range)) · \(syntaxText)",
                subtitle: compactTitle
                    ? slotSubtitle(syntax.nextSlot)
                    : splitSubtitle,
                systemImage: compactTitle
                    ? slotSystemImage(syntax.nextSlot)
                    : "arrow.triangle.branch",
                bindings: [valueBinding, connectorBinding],
                nextSlot: syntax.nextSlot,
                score: 9_400
            )
        }

        private func slotSubtitle(_ slot: ComposerSlot) -> String? {
            ComposerSlotPresentation.subtitle(for: slot)
        }

        private func slotSystemImage(_ slot: ComposerSlot) -> String {
            ComposerSlotPresentation.systemImage(for: slot)
        }

        private func snapshot(
            spans: [ComposerSemanticSpan],
            clauses: [ComposerParsedClauseRange],
            fallbackRange: Range<Int>,
            fallbackSlot: ComposerSlot,
            fallbackQuery: String,
            continuation: ComposerContinuationContext?,
            alternatives: [ComposerParseAlternative],
            syntaxValid: Bool
        ) -> ComposerParseSnapshot {
            let selection = clamped(input.selection)
            if let selected = selectedSpan(in: spans, selection: selection) {
                return ComposerParseSnapshot(
                    spans: spans,
                    clauseRanges: clauses,
                    activeRange: selected.range,
                    activeSlot: selected.token.role.slot,
                    activeQuery: substring(selected.range),
                    continuation: nil,
                    alternatives: alternatives,
                    isSyntaxValid: syntaxValid
                )
            }
            if !selection.isEmpty {
                return ComposerParseSnapshot(
                    spans: spans,
                    clauseRanges: clauses,
                    activeRange: selection,
                    activeSlot: fallbackSlot,
                    activeQuery: substring(selection),
                    continuation: nil,
                    alternatives: alternatives,
                    isSyntaxValid: syntaxValid
                )
            }
            if let clause = clauses.last(where: {
                $0.range.contains(selection.lowerBound)
                    || $0.range.upperBound == selection.lowerBound
            }), selection.lowerBound < textLength {
                let range = trimmed(clause.range)
                return ComposerParseSnapshot(
                    spans: spans,
                    clauseRanges: clauses,
                    activeRange: range,
                    activeSlot: clause.slot,
                    activeQuery: substring(range),
                    continuation: nil,
                    alternatives: alternatives,
                    isSyntaxValid: syntaxValid
                )
            }
            return ComposerParseSnapshot(
                spans: spans,
                clauseRanges: clauses,
                activeRange: fallbackRange,
                activeSlot: fallbackSlot,
                activeQuery: fallbackQuery,
                continuation: continuation,
                alternatives: alternatives,
                isSyntaxValid: syntaxValid
            )
        }

        private func invalidSnapshot(
            spans: [ComposerSemanticSpan],
            clauses: [ComposerParsedClauseRange],
            range: Range<Int>,
            slot: ComposerSlot
        ) -> ComposerParseSnapshot {
            snapshot(
                spans: spans,
                clauses: clauses,
                fallbackRange: range,
                fallbackSlot: slot,
                fallbackQuery: substring(range),
                continuation: nil,
                alternatives: [],
                syntaxValid: false
            )
        }

        private func selectedSpan(
            in spans: [ComposerSemanticSpan],
            selection: Range<Int>
        ) -> ComposerSemanticSpan? {
            spans.first {
                if !selection.isEmpty {
                    return $0.range.lowerBound <= selection.lowerBound
                        && $0.range.upperBound >= selection.upperBound
                }
                return $0.range.contains(selection.lowerBound)
                    || (
                        $0.range.upperBound == selection.lowerBound
                            && selection.lowerBound > 0
                            && !character(before: selection.lowerBound)
                                .isWhitespace
                    )
            }
        }

        private func resolveBindingToken(
            _ binding: ComposerSemanticBinding
        ) -> ComposerToken {
            token(
                from: binding.token,
                displayText: substring(binding.range)
            )
        }

        private func token(
            from token: ComposerToken,
            displayText: String
        ) -> ComposerToken {
            let canonicalValue: ComposerTokenValue
            switch token.value {
            case .person(let person):
                canonicalValue = input.people.first {
                    $0.id == person.id
                }.map(ComposerTokenValue.person) ?? token.value
            case .location(let candidate, let role)
                where candidate.source == .savedPlace
                    && candidate.savedPlaceID != nil:
                canonicalValue = input.locations.first {
                    $0.source == .savedPlace
                        && savedPlaceIdentityMatches($0, candidate)
                }.map {
                    ComposerTokenValue.location($0, role)
                } ?? token.value
            default:
                canonicalValue = token.value
            }
            return ComposerToken(
                id: token.id,
                displayText: displayText,
                value: canonicalValue
            )
        }

        private func binding(
            exactly range: Range<Int>,
            role: ComposerValueRole
        ) -> ComposerSemanticBinding? {
            input.bindings.first {
                $0.range == range
                    && $0.token.role == role
                    && bindingStillMatches($0)
            }
        }

        private func hasCommittedBoundary(
            valueRange: Range<Int>,
            connectorRange: Range<Int>
        ) -> Bool {
            input.bindings.contains {
                $0.range == valueRange && bindingStillMatches($0)
            } && input.bindings.contains {
                $0.range == connectorRange
                    && $0.token.role == .connector
                    && bindingStillMatches($0)
            }
        }

        private func bindingStillMatches(
            _ binding: ComposerSemanticBinding
        ) -> Bool {
            guard binding.range.lowerBound >= 0,
                  binding.range.upperBound <= textLength,
                  !binding.range.isEmpty,
                  semanticIdentityIsAvailable(binding.token) else {
                return false
            }
            return normalized(substring(binding.range))
                == normalized(binding.token.displayText)
        }

        private func semanticIdentityIsAvailable(
            _ token: ComposerToken
        ) -> Bool {
            switch token.value {
            case .leading(.transit(let canonicalName)):
                return input.transitTypes.contains {
                    $0.canonicalName == canonicalName
                }
            case .person(let person):
                return input.people.contains { $0.id == person.id }
            case .location(let candidate, _):
                guard candidate.source == .savedPlace,
                      candidate.savedPlaceID != nil else {
                    return true
                }
                return input.locations.contains {
                    $0.source == .savedPlace
                        && savedPlaceIdentityMatches($0, candidate)
                }
            case .leading, .connector, .time, .duration:
                return true
            }
        }

        private func savedPlaceIdentityMatches(
            _ lhs: ComposerLocationCandidate,
            _ rhs: ComposerLocationCandidate
        ) -> Bool {
            guard let lhsID = lhs.savedPlaceID,
                  let rhsID = rhs.savedPlaceID else {
                return false
            }
            return lhsID == rhsID
        }

        private func hasLongerLeadingMatch(_ query: String) -> Bool {
            let terms = ["Stay"] + input.transitTypes.flatMap {
                [$0.canonicalName] + $0.aliases
            }
            return terms.contains { isLonger($0, than: query) }
        }

        private func isLonger(_ candidate: String, than query: String) -> Bool {
            let candidate = normalized(candidate)
            let query = normalized(query)
            guard candidate.count > query.count else { return false }
            return candidate.hasPrefix(query + " ")
                || candidate.hasPrefix(query + "-")
                || candidate.hasPrefix(query + " -")
        }

        private func timeZone(
            for role: ComposerTimeRole,
            parsedTokens: [ComposerToken]
        ) -> TimeZone {
            let kind: ComposerEntryKind? = parsedTokens.compactMap {
                token -> ComposerEntryKind? in
                guard case .leading(let kind) = token.value else {
                    return nil
                }
                return kind
            }.first
            let locationRole: ComposerLocationRole = switch kind {
            case .placeVisit:
                .visit
            case .transit:
                role == .start ? .origin : .destination
            case nil:
                role == .start ? .origin : .destination
            }
            let identifier: String? = parsedTokens.reversed().compactMap {
                token -> String? in
                guard case .location(let candidate, let role) = token.value,
                      role == locationRole else {
                    return nil
                }
                return candidate.location.timeZoneIdentifier
            }.first
            return TimeZone(identifier: identifier ?? "") ?? .current
        }

        private func syntaxIsComplete(_ syntax: ClauseSyntax) -> Bool {
            if syntax.isPersonSeparator,
               let segment = segment(startingAt: syntax.range.lowerBound),
               segment.text == "," || segment.text == "&" {
                return true
            }
            return syntax.range.upperBound < textLength
                && character(at: syntax.range.upperBound).isWhitespace
                || input.bindings.contains {
                    $0.range == syntax.range
                        && $0.token.role == .connector
                        && bindingStillMatches($0)
                }
        }

        private func connector(for text: String) -> ComposerConnector? {
            ComposerConnector(rawValue: normalized(text))
        }

        private func isPersonSeparator(_ text: String) -> Bool {
            let value = normalized(text)
            return value == "," || value == "and" || value == "&"
        }

        private func segment(startingAt offset: Int) -> ComposerTextSegment? {
            segments.first { $0.range.lowerBound == offset }
        }

        private func skipWhitespace(from offset: Int) -> Int {
            var result = min(max(0, offset), textLength)
            while result < textLength, character(at: result).isWhitespace {
                result += 1
            }
            return result
        }

        private func trimmed(_ range: Range<Int>) -> Range<Int> {
            source.trimmingWhitespace(in: range)
        }

        private func substring(_ range: Range<Int>) -> String {
            source.substring(in: range)
        }

        private func character(at offset: Int) -> Character {
            source.character(at: offset) ?? " "
        }

        private func character(before offset: Int) -> Character {
            source.character(before: offset) ?? " "
        }

        private func clamped(_ range: Range<Int>) -> Range<Int> {
            source.clamped(range)
        }

        private func nonWhitespaceIsCovered(
            by ranges: [Range<Int>]
        ) -> Bool {
            source.nonWhitespaceIsCovered(by: ranges)
        }

        private func normalized(_ value: String) -> String {
            GuidedComposerNormalization.text(value)
        }

    }
}
