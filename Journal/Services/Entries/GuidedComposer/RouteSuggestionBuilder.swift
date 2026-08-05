import Foundation

struct GuidedComposerRouteSuggestionInput {
    let routingMode: TransitRoutingMode
    let context: ComposerTimelineContext
    let homeCandidates: [ComposerLocationCandidate]
    let isToday: Bool
    let currentLocation: Location?
    let draft: ComposerDraft
    let anchorToEnd: Bool

    var shouldCalculate: Bool {
        let origin = draft.location(.origin)
        let destination = draft.location(.destination)
        let hasDistinctRoute = if let origin, let destination {
            !GuidedComposerLocationMatcher.sameLocation(origin, destination)
        } else {
            false
        }
        return hasDistinctRoute || !context.intervals.isEmpty
    }
}

struct GuidedComposerRouteSuggestionState: Equatable {
    let suggestions: [ComposerSuggestion]
    let durationSuggestion: ComposerSuggestion?
    let routeDuration: ComposerDurationValue?
    let isCalculating: Bool

    static let empty = GuidedComposerRouteSuggestionState(
        suggestions: [],
        durationSuggestion: nil,
        routeDuration: nil,
        isCalculating: false
    )
}

@MainActor
enum GuidedComposerRouteSuggestionBuilder {
    static func build(
        input: GuidedComposerRouteSuggestionInput,
        durationCache: GuidedComposerRouteDurationCache,
        onUpdate: @escaping @MainActor (
            GuidedComposerRouteSuggestionState
        ) -> Void
    ) async {
        let routingMode = input.routingMode
        let context = input.context
        let draft = input.draft
        let selectedOrigin = draft.location(.origin)
        let selectedDestination = draft.location(.destination)
        let hasDistinctSelectedRoute = if let selectedOrigin,
                                          let selectedDestination {
            !GuidedComposerLocationMatcher.sameLocation(
                selectedOrigin,
                selectedDestination
            )
        } else {
            false
        }
        let relevantGaps = context.gaps.filter {
            GuidedComposerRouteInference.endpointsMatchCommittedContext(
                origin: $0.origin,
                destination: $0.destination,
                draft: draft,
                replacing: nil
            )
        }

        var suggestions: [ComposerSuggestion] = []
        var durationSuggestion: ComposerSuggestion?
        var routeDuration: ComposerDurationValue?
        var selectedRouteDuration: TimeInterval?

        func publish(isCalculating: Bool = true) {
            var seen = Set<String>()
            let deduplicated = suggestions.filter {
                seen.insert($0.id).inserted
            }
            onUpdate(
                GuidedComposerRouteSuggestionState(
                    suggestions: deduplicated,
                    durationSuggestion: durationSuggestion,
                    routeDuration: routeDuration,
                    isCalculating: isCalculating
                )
            )
        }

        if hasDistinctSelectedRoute,
           let selectedOrigin,
           let selectedDestination,
           let duration = await durationCache.duration(
               from: selectedOrigin,
               to: selectedDestination,
               routingMode: routingMode
           ) {
            guard !Task.isCancelled else { return }
            selectedRouteDuration = duration
            let source = durationSource(for: routingMode)
            let value = ComposerDurationValue(
                interval: duration,
                source: source
            )
            routeDuration = value
            durationSuggestion = ComposerSuggestion(
                id:
                    "duration-mapkit-\(selectedOrigin.id)-\(selectedDestination.id)",
                title: GuidedComposerTimeParser.displayDuration(duration),
                subtitle: String(localized: "MapKit estimate"),
                systemImage: "map",
                kind: .value(
                    tokens: [
                        ComposerToken(
                            displayText:
                                GuidedComposerTimeParser.displayDuration(
                                    duration
                                ),
                            value: .duration(value)
                        ),
                    ],
                    nextSlot: .connector
                ),
                score: 10_000
            )
            publish()

            if input.isToday, let currentLocation = input.currentLocation {
                let nearOrigin = GuidedComposerRouteInference
                    .isInsideEffectiveRadius(
                        currentLocation,
                        of: selectedOrigin
                    )
                let nearDestination = GuidedComposerRouteInference
                    .isInsideEffectiveRadius(
                        currentLocation,
                        of: selectedDestination
                    )
                if nearOrigin != nearDestination {
                    let now = Date.now
                    let start = nearOrigin
                        ? now
                        : now.addingTimeInterval(-duration)
                    let end = nearOrigin
                        ? now.addingTimeInterval(duration)
                        : now
                    suggestions.append(
                        GuidedComposerRouteInference.routeSuggestion(
                            id:
                                "route-gps-selected-\(selectedOrigin.id)-\(selectedDestination.id)",
                            origin: selectedOrigin,
                            destination: selectedDestination,
                            start: start,
                            end: end,
                            timeSource: nearOrigin
                                ? .nearOrigin
                                : .nearDestination,
                            durationSource: source,
                            subtitle: nearOrigin
                                ? String(localized: "Leave from here now")
                                : String(localized: "Arrived here now"),
                            score: 7_800
                        )
                    )
                    publish()
                }
            }
        }

        let anchoredRequests = GuidedComposerRouteInference
            .anchoredRouteRequests(
                in: context,
                selectedOrigin: selectedOrigin,
                selectedDestination: selectedDestination
            )
        for request in anchoredRequests {
            guard !Task.isCancelled else { return }
            let duration: TimeInterval?
            if let selectedOrigin,
               let selectedDestination,
               GuidedComposerLocationMatcher.sameLocation(
                   selectedOrigin,
                   request.origin
               ),
               GuidedComposerLocationMatcher.sameLocation(
                   selectedDestination,
                   request.destination
               ) {
                duration = selectedRouteDuration
            } else {
                duration = await durationCache.duration(
                    from: request.origin,
                    to: request.destination,
                    routingMode: routingMode
                )
            }
            guard !Task.isCancelled else { return }
            guard let duration else { continue }
            let interval = request.interval(for: duration)
            guard context.containsSelectedDayInterval(
                start: interval.start,
                end: interval.end
            ) else {
                continue
            }
            suggestions.append(
                GuidedComposerRouteInference.routeSuggestion(
                    id: request.id,
                    origin: request.origin,
                    destination: request.destination,
                    start: interval.start,
                    end: interval.end,
                    timeSource: .history,
                    durationSource: durationSource(for: routingMode),
                    subtitle: request.subtitle,
                    score: request.score
                )
            )
            publish()
        }

        for (index, gap) in relevantGaps.enumerated() {
            guard !Task.isCancelled else { return }
            guard let duration = await durationCache.duration(
                from: gap.origin,
                to: gap.destination,
                routingMode: routingMode
            ) else {
                continue
            }
            guard !Task.isCancelled else { return }
            let gapDuration = gap.endTime.timeIntervalSince(gap.startTime)
            let source = durationSource(for: routingMode)

            if GuidedComposerRouteInference.shouldOfferMapKitAlternative(
                gapDuration: gapDuration,
                routeDuration: duration
            ) {
                let start = input.anchorToEnd
                    ? gap.endTime.addingTimeInterval(-duration)
                    : gap.startTime
                let end = input.anchorToEnd
                    ? gap.endTime
                    : gap.startTime.addingTimeInterval(duration)
                suggestions.append(
                    GuidedComposerRouteInference.routeSuggestion(
                        id: "route-mapkit-\(gap.id)",
                        origin: gap.origin,
                        destination: gap.destination,
                        start: start,
                        end: end,
                        timeSource: .history,
                        durationSource: source,
                        subtitle: String(
                            localized:
                                "MapKit duration, anchored to timeline"
                        ),
                        score: 8_500 - index
                    )
                )
            }

            if input.isToday, let currentLocation = input.currentLocation {
                let nearOrigin = GuidedComposerRouteInference
                    .isInsideEffectiveRadius(
                        currentLocation,
                        of: gap.origin
                    )
                let nearDestination = GuidedComposerRouteInference
                    .isInsideEffectiveRadius(
                        currentLocation,
                        of: gap.destination
                    )
                if nearOrigin != nearDestination {
                    let now = Date.now
                    let start = nearOrigin
                        ? now
                        : now.addingTimeInterval(-duration)
                    let end = nearOrigin
                        ? now.addingTimeInterval(duration)
                        : now
                    guard start >= gap.startTime,
                          end <= gap.endTime else {
                        continue
                    }
                    suggestions.append(
                        GuidedComposerRouteInference.routeSuggestion(
                            id: "route-gps-\(gap.id)",
                            origin: gap.origin,
                            destination: gap.destination,
                            start: start,
                            end: end,
                            timeSource: nearOrigin
                                ? .nearOrigin
                                : .nearDestination,
                            durationSource: source,
                            subtitle: nearOrigin
                                ? String(localized: "Near origin now")
                                : String(localized: "Near destination now"),
                            score: 7_500 - index
                        )
                    )
                }
            }
        }

        if let first = context.intervals.first,
           GuidedComposerTimelineInference.shouldOfferLeadingHomeRoute(
               in: context
           ) {
            let homes = GuidedComposerLocationRanking.rankedHomeCandidates(
                input.homeCandidates,
                near: first.startLocation
            )
            for (index, home) in homes.enumerated() {
                guard !Task.isCancelled else { return }
                guard let duration = await durationCache.duration(
                    from: home,
                    to: first.startLocation,
                    routingMode: routingMode
                ) else {
                    continue
                }
                guard !Task.isCancelled else { return }
                let start = first.startTime.addingTimeInterval(-duration)
                guard context.containsSelectedDayInterval(
                    start: start,
                    end: first.startTime
                ) else {
                    continue
                }
                suggestions.append(
                    GuidedComposerRouteInference.routeSuggestion(
                        id: "route-before-\(first.id)-\(home.id)",
                        origin: home,
                        destination: first.startLocation,
                        start: start,
                        end: first.startTime,
                        timeSource: .history,
                        durationSource: durationSource(for: routingMode),
                        subtitle: String(
                            localized: "Arrive before \(first.label)"
                        ),
                        score: 7_200 - index
                    )
                )
            }
        }

        if let last = context.intervals.last,
           GuidedComposerTimelineInference.shouldOfferTrailingHomeRoute(
               in: context
           ) {
            let homes = GuidedComposerLocationRanking.rankedHomeCandidates(
                input.homeCandidates,
                near: last.endLocation
            )
            for (index, home) in homes.enumerated() {
                guard !Task.isCancelled else { return }
                guard let duration = await durationCache.duration(
                    from: last.endLocation,
                    to: home,
                    routingMode: routingMode
                ) else {
                    continue
                }
                guard !Task.isCancelled else { return }
                let end = last.endTime.addingTimeInterval(duration)
                guard context.containsSelectedDayInterval(
                    start: last.endTime,
                    end: end
                ) else {
                    continue
                }
                suggestions.append(
                    GuidedComposerRouteInference.routeSuggestion(
                        id: "route-after-\(last.id)-\(home.id)",
                        origin: last.endLocation,
                        destination: home,
                        start: last.endTime,
                        end: end,
                        timeSource: .history,
                        durationSource: durationSource(for: routingMode),
                        subtitle: String(
                            localized: "Leave after \(last.label)"
                        ),
                        score: 7_000 - index
                    )
                )
            }
        }

        guard !Task.isCancelled else { return }
        publish(isCalculating: false)
    }

    private static func durationSource(
        for routingMode: TransitRoutingMode
    ) -> DurationSource {
        routingMode == .walking ? .mapkitWalking : .mapkitCarFallback
    }
}
