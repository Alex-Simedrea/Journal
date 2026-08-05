import Foundation

enum ComposerRouteTimeAnchor: Equatable, Sendable {
    case arrival(Date)
    case departure(Date)
}

struct ComposerAnchoredRouteRequest: Equatable, Sendable {
    let id: String
    let origin: ComposerLocationCandidate
    let destination: ComposerLocationCandidate
    let anchor: ComposerRouteTimeAnchor
    let subtitle: String
    let score: Int

    func interval(for duration: TimeInterval) -> (start: Date, end: Date) {
        switch anchor {
        case .arrival(let end):
            (end.addingTimeInterval(-duration), end)
        case .departure(let start):
            (start, start.addingTimeInterval(duration))
        }
    }
}

@MainActor
enum GuidedComposerRouteInference {
    static func shouldOfferMapKitAlternative(
        gapDuration: TimeInterval,
        routeDuration: TimeInterval
    ) -> Bool {
        let difference = abs(gapDuration - routeDuration)
        guard difference
            >= GuidedComposerPolicy.minimumRouteAlternativeDifference else {
            return false
        }
        return difference / max(gapDuration, 1) >= 0.25
    }

    static func routeSuggestion(
        id: String,
        origin: ComposerLocationCandidate,
        destination: ComposerLocationCandidate,
        start: Date,
        end: Date,
        timeSource: ComposerTimeSource,
        durationSource: DurationSource,
        subtitle: String,
        score: Int
    ) -> ComposerSuggestion {
        let originZone = TimeZone(
            identifier: origin.location.timeZoneIdentifier ?? ""
        ) ?? .current
        let destinationZone = TimeZone(
            identifier: destination.location.timeZoneIdentifier ?? ""
        ) ?? .current
        let tokens = GuidedComposerTimelineInference.routeTokens(
            origin: origin,
            start: ComposerTimeValue(
                date: start,
                timeZoneIdentifier: originZone.identifier,
                source: timeSource,
                durationSource: durationSource
            ),
            destination: destination,
            end: ComposerTimeValue(
                date: end,
                timeZoneIdentifier: destinationZone.identifier,
                source: timeSource,
                durationSource: durationSource
            )
        )
        return ComposerSuggestion(
            id: id,
            title: tokens.map(\.displayText).joined(separator: " "),
            subtitle: subtitle,
            systemImage: "point.bottomleft.forward.to.point.topright.scurvepath",
            kind: .macro(tokens: tokens, nextSlot: .connector),
            score: score
        )
    }

    static func isInsideEffectiveRadius(
        _ currentLocation: Location,
        of candidate: ComposerLocationCandidate
    ) -> Bool {
        GuidedComposerLocationMatcher.distanceMeters(
            currentLocation,
            candidate.location
        ) <= max(
            GuidedComposerPolicy.minimumCurrentLocationRadiusMeters,
            candidate.accuracyRadiusMeters
        )
    }

    static func derivedBoundaryTime(
        role: ComposerTimeRole,
        start: Date?,
        end: Date?,
        duration: TimeInterval
    ) -> Date? {
        switch role {
        case .start:
            end?.addingTimeInterval(-duration)
        case .end:
            start?.addingTimeInterval(duration)
        }
    }

    static func anchoredRouteRequests(
        in context: ComposerTimelineContext,
        selectedOrigin: ComposerLocationCandidate?,
        selectedDestination: ComposerLocationCandidate?
    ) -> [ComposerAnchoredRouteRequest] {
        var requests: [ComposerAnchoredRouteRequest] = []

        if let selectedOrigin {
            let occursOnTimeline = contextContains(
                selectedOrigin,
                in: context
            )
            if !occursOnTimeline {
                for (index, interval) in context.intervals.enumerated()
                where GuidedComposerTimelineInference.hasInferenceWindow(
                    before: index,
                    in: context
                ) && context.containsSelectedDayBoundary(
                    interval.startTime
                ) {
                    appendArrivalRequest(
                        origin: selectedOrigin,
                        destination: interval.startLocation,
                        destinationConstraint: selectedDestination,
                        boundaryID: interval.id.uuidString,
                        arrival: interval.startTime,
                        label: interval.label,
                        score: 9_800 - index,
                        to: &requests
                    )
                }
            }
        }

        if let selectedDestination {
            let occursOnTimeline = contextContains(
                selectedDestination,
                in: context
            )
            if !occursOnTimeline {
                for (index, interval) in context.intervals.enumerated()
                where GuidedComposerTimelineInference.hasInferenceWindow(
                    after: index,
                    in: context
                ) && context.containsSelectedDayBoundary(
                    interval.endTime
                ) {
                    appendDepartureRequest(
                        origin: interval.endLocation,
                        originConstraint: selectedOrigin,
                        destination: selectedDestination,
                        boundaryID: interval.id.uuidString,
                        departure: interval.endTime,
                        label: interval.label,
                        score: 9_600 - index,
                        to: &requests
                    )
                }
            }
        }

        return requests
    }

    private static func contextContains(
        _ location: ComposerLocationCandidate,
        in context: ComposerTimelineContext
    ) -> Bool {
        context.intervals.contains {
            GuidedComposerLocationMatcher.sameLocation(
                $0.startLocation,
                location
            )
                || GuidedComposerLocationMatcher.sameLocation(
                    $0.endLocation,
                    location
                )
        }
    }

    private static func appendArrivalRequest(
        origin: ComposerLocationCandidate,
        destination: ComposerLocationCandidate,
        destinationConstraint: ComposerLocationCandidate?,
        boundaryID: String,
        arrival: Date,
        label: String,
        score: Int,
        to requests: inout [ComposerAnchoredRouteRequest]
    ) {
        guard !GuidedComposerLocationMatcher.sameLocation(
            origin,
            destination
        ),
        destinationConstraint.map({
            GuidedComposerLocationMatcher.sameLocation(
                $0,
                destination
            )
        }) ?? true else {
            return
        }
        requests.append(
            ComposerAnchoredRouteRequest(
                id: "route-to-boundary-\(origin.id)-\(boundaryID)",
                origin: origin,
                destination: destination,
                anchor: .arrival(arrival),
                subtitle: String(localized: "Arrive before \(label)"),
                score: score
            )
        )
    }

    private static func appendDepartureRequest(
        origin: ComposerLocationCandidate,
        originConstraint: ComposerLocationCandidate?,
        destination: ComposerLocationCandidate,
        boundaryID: String,
        departure: Date,
        label: String,
        score: Int,
        to requests: inout [ComposerAnchoredRouteRequest]
    ) {
        guard !GuidedComposerLocationMatcher.sameLocation(
            origin,
            destination
        ),
        originConstraint.map({
            GuidedComposerLocationMatcher.sameLocation(
                $0,
                origin
            )
        }) ?? true else {
            return
        }
        requests.append(
            ComposerAnchoredRouteRequest(
                id: "route-from-boundary-\(boundaryID)-\(destination.id)",
                origin: origin,
                destination: destination,
                anchor: .departure(departure),
                subtitle: String(localized: "Leave after \(label)"),
                score: score
            )
        )
    }

    static func contextualLocations(
        from routes: [ComposerSuggestion],
        draft: ComposerDraft,
        role: ComposerLocationRole
    ) -> [ComposerLocationCandidate] {
        guard role != .visit else { return [] }
        var result: [ComposerLocationCandidate] = []
        for route in routes {
            guard let values = routeValues(in: route),
                  routeMatchesCommittedContext(
                      values,
                      draft: draft,
                      replacing: role
                  ) else {
                continue
            }
            let candidate = role == .origin
                ? values.origin
                : values.destination
            guard !result.contains(where: {
                GuidedComposerLocationMatcher.sameLocation(
                    $0,
                    candidate
                )
            }) else {
                continue
            }
            result.append(candidate)
        }
        return result
    }

    static func endpointsMatchCommittedContext(
        origin: ComposerLocationCandidate,
        destination: ComposerLocationCandidate,
        draft: ComposerDraft,
        replacing role: ComposerLocationRole?
    ) -> Bool {
        if role != .origin, let selectedOrigin = draft.location(.origin),
           !GuidedComposerLocationMatcher.sameLocation(
               selectedOrigin,
               origin
           ) {
            return false
        }
        if role != .destination,
           let selectedDestination = draft.location(.destination),
           !GuidedComposerLocationMatcher.sameLocation(
               selectedDestination,
               destination
           ) {
            return false
        }
        return true
    }

    static func projectedSuggestions(
        from routes: [ComposerSuggestion],
        draft: ComposerDraft,
        activeSlot: ComposerSlot,
        query: String
    ) -> [ComposerSuggestion] {
        routes.compactMap { route in
            guard let values = routeValues(in: route) else { return nil }
            let replacingRole: ComposerLocationRole? = switch activeSlot {
            case .location(let role): role
            default: nil
            }
            guard routeMatchesCommittedContext(
                values,
                draft: draft,
                replacing: replacingRole
            ) else {
                return nil
            }

            let tokens: [ComposerToken]
            let queryScore: Int
            let canSuggestRouteTimes = draft.time(.start) == nil
                && draft.time(.end) == nil
                && draft.duration == nil
            switch activeSlot {
            case .connector:
                guard GuidedComposerNormalization.text(query).isEmpty else {
                    return nil
                }
                guard canSuggestRouteTimes else { return nil }
                tokens = connectorCompletion(
                    values,
                    hasOrigin: draft.location(.origin) != nil,
                    hasDestination: draft.location(.destination) != nil,
                    hasStart: draft.time(.start) != nil,
                    hasEnd: draft.time(.end) != nil
                )
                queryScore = 0

            case .location(.origin):
                guard let score = GuidedComposerRanking.textScore(
                    query: query,
                    candidates: values.origin.allSearchTerms
                ) else {
                    return nil
                }
                tokens = originCompletion(
                    values,
                    hasDestination:
                        draft.location(.destination) != nil,
                    includeTimes: canSuggestRouteTimes
                )
                queryScore = score

            case .location(.destination):
                guard let score = GuidedComposerRanking.textScore(
                    query: query,
                    candidates: values.destination.allSearchTerms
                ) else {
                    return nil
                }
                tokens = destinationCompletion(
                    values,
                    hasOrigin: draft.location(.origin) != nil,
                    includeTimes: canSuggestRouteTimes
                )
                queryScore = score

            case .time(.start):
                guard canSuggestRouteTimes else { return nil }
                var timeTokens = [
                    timeToken(values.start, role: .start),
                ]
                if draft.location(.destination) == nil {
                    timeTokens += [
                        connectorToken(.to),
                        locationToken(
                            values.destination,
                            role: .destination
                        ),
                        connectorToken(.at),
                        timeToken(values.end, role: .end),
                    ]
                } else if draft.time(.end) == nil {
                    timeTokens += [
                        connectorToken(.to),
                        timeToken(values.end, role: .end),
                    ]
                }
                tokens = timeTokens
                guard let score = GuidedComposerRanking.textScore(
                    query: query,
                    candidates: [tokens[0].displayText]
                ) else {
                    return nil
                }
                queryScore = score

            case .time(.end):
                guard canSuggestRouteTimes else { return nil }
                var timeTokens = [
                    timeToken(values.end, role: .end),
                ]
                if draft.location(.origin) == nil {
                    timeTokens += [
                        connectorToken(.from),
                        locationToken(values.origin, role: .origin),
                        connectorToken(.at),
                        timeToken(values.start, role: .start),
                    ]
                } else if draft.time(.start) == nil {
                    timeTokens += [
                        connectorToken(.from),
                        timeToken(values.start, role: .start),
                    ]
                }
                tokens = timeTokens
                guard let score = GuidedComposerRanking.textScore(
                    query: query,
                    candidates: [tokens[0].displayText]
                ) else {
                    return nil
                }
                queryScore = score

            case .leading, .duration, .person, .location(.visit):
                return nil
            }

            guard !tokens.isEmpty else { return nil }
            return ComposerSuggestion(
                id: "\(route.id)-projected-\(activeSlot)",
                title: tokens.map(\.displayText).joined(separator: " "),
                subtitle: route.subtitle,
                systemImage: route.systemImage,
                kind: .macro(tokens: tokens, nextSlot: .connector),
                score: route.score + 30_000 + queryScore
            )
        }
    }

    private static func routeMatchesCommittedContext(
        _ values: RouteValues,
        draft: ComposerDraft,
        replacing role: ComposerLocationRole?
    ) -> Bool {
        guard endpointsMatchCommittedContext(
            origin: values.origin,
            destination: values.destination,
            draft: draft,
            replacing: role
        ) else {
            return false
        }
        if let selectedStart = draft.time(.start)?.date,
           abs(selectedStart.timeIntervalSince(values.start.date)) > 60 {
            return false
        }
        if let selectedEnd = draft.time(.end)?.date,
           abs(selectedEnd.timeIntervalSince(values.end.date)) > 60 {
            return false
        }
        if let duration = draft.duration,
           abs(
               values.end.date.timeIntervalSince(values.start.date)
                   - duration
           ) > 60 {
            return false
        }
        return true
    }

    private static func connectorCompletion(
        _ values: RouteValues,
        hasOrigin: Bool,
        hasDestination: Bool,
        hasStart: Bool,
        hasEnd: Bool
    ) -> [ComposerToken] {
        if !hasOrigin, !hasDestination {
            return [
                connectorToken(.from),
                locationToken(values.origin, role: .origin),
                connectorToken(.at),
                timeToken(values.start, role: .start),
                connectorToken(.to),
                locationToken(values.destination, role: .destination),
                connectorToken(.at),
                timeToken(values.end, role: .end),
            ]
        }
        if hasOrigin, !hasDestination {
            var tokens = [
                connectorToken(.to),
                locationToken(values.destination, role: .destination),
            ]
            if !hasEnd {
                tokens += [
                    connectorToken(.at),
                    timeToken(values.end, role: .end),
                ]
            }
            if !hasStart {
                tokens += [
                    connectorToken(.from),
                    timeToken(values.start, role: .start),
                ]
            }
            return tokens
        }
        if !hasOrigin, hasDestination {
            var tokens = [
                connectorToken(.from),
                locationToken(values.origin, role: .origin),
            ]
            if !hasStart {
                tokens += [
                    connectorToken(.at),
                    timeToken(values.start, role: .start),
                ]
            }
            if !hasEnd {
                tokens += [
                    connectorToken(.to),
                    timeToken(values.end, role: .end),
                ]
            }
            return tokens
        }

        var tokens: [ComposerToken] = []
        if !hasStart {
            tokens += [
                connectorToken(.from),
                timeToken(values.start, role: .start),
            ]
        }
        if !hasEnd {
            tokens += [
                connectorToken(.to),
                timeToken(values.end, role: .end),
            ]
        }
        return tokens
    }

    private static func originCompletion(
        _ values: RouteValues,
        hasDestination: Bool,
        includeTimes: Bool
    ) -> [ComposerToken] {
        var tokens = [
            locationToken(values.origin, role: .origin),
        ]
        if includeTimes {
            tokens += [
                connectorToken(.at),
                timeToken(values.start, role: .start),
            ]
        }
        if !hasDestination {
            tokens += [
                connectorToken(.to),
                locationToken(values.destination, role: .destination),
            ]
            if includeTimes {
                tokens += [
                    connectorToken(.at),
                    timeToken(values.end, role: .end),
                ]
            }
        } else if includeTimes {
            tokens += [
                connectorToken(.to),
                timeToken(values.end, role: .end),
            ]
        }
        return tokens
    }

    private static func destinationCompletion(
        _ values: RouteValues,
        hasOrigin: Bool,
        includeTimes: Bool
    ) -> [ComposerToken] {
        var tokens = [
            locationToken(values.destination, role: .destination),
        ]
        if includeTimes {
            tokens += [
                connectorToken(.at),
                timeToken(values.end, role: .end),
            ]
        }
        if !hasOrigin {
            tokens += [
                connectorToken(.from),
                locationToken(values.origin, role: .origin),
            ]
            if includeTimes {
                tokens += [
                    connectorToken(.at),
                    timeToken(values.start, role: .start),
                ]
            }
        } else if includeTimes {
            tokens += [
                connectorToken(.from),
                timeToken(values.start, role: .start),
            ]
        }
        return tokens
    }

    private static func connectorToken(
        _ connector: ComposerConnector
    ) -> ComposerToken {
        ComposerTokenFactory.connector(connector)
    }

    private static func locationToken(
        _ location: ComposerLocationCandidate,
        role: ComposerLocationRole
    ) -> ComposerToken {
        ComposerTokenFactory.location(location, role: role)
    }

    private static func timeToken(
        _ value: ComposerTimeValue,
        role: ComposerTimeRole
    ) -> ComposerToken {
        ComposerTokenFactory.time(value, role: role)
    }

    private static func routeValues(
        in suggestion: ComposerSuggestion
    ) -> RouteValues? {
        guard case .macro(let tokens, _) = suggestion.kind,
              let origin = tokens.compactMap({
                  token -> ComposerLocationCandidate? in
                  guard case .location(let value, .origin) = token.value else {
                      return nil
                  }
                  return value
              }).first,
              let destination = tokens.compactMap({
                  token -> ComposerLocationCandidate? in
                  guard case .location(let value, .destination) = token.value
                  else {
                      return nil
                  }
                  return value
              }).first,
              let start = tokens.compactMap({
                  token -> ComposerTimeValue? in
                  guard case .time(let value, .start) = token.value else {
                      return nil
                  }
                  return value
              }).first,
              let end = tokens.compactMap({
                  token -> ComposerTimeValue? in
                  guard case .time(let value, .end) = token.value else {
                      return nil
                  }
                  return value
              }).first else {
            return nil
        }
        return RouteValues(
            origin: origin,
            start: start,
            destination: destination,
            end: end
        )
    }

    private struct RouteValues {
        let origin: ComposerLocationCandidate
        let start: ComposerTimeValue
        let destination: ComposerLocationCandidate
        let end: ComposerTimeValue
    }
}
