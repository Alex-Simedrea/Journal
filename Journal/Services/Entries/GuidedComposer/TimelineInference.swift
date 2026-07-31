import Foundation

struct ComposerTimelineInterval: Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: LogKind
    let label: String
    let startTime: Date
    let endTime: Date
    let startLocation: ComposerLocationCandidate
    let endLocation: ComposerLocationCandidate
}

struct ComposerTimelineGap: Equatable, Identifiable, Sendable {
    let previous: ComposerTimelineInterval
    let next: ComposerTimelineInterval

    var id: String {
        "\(previous.id.uuidString)-\(next.id.uuidString)"
    }

    var startTime: Date { previous.endTime }
    var endTime: Date { next.startTime }
    var origin: ComposerLocationCandidate { previous.endLocation }
    var destination: ComposerLocationCandidate { next.startLocation }
}

struct ComposerTimelineContext: Equatable, Sendable {
    let intervals: [ComposerTimelineInterval]
    let gaps: [ComposerTimelineGap]
    let endpointCandidates: [ComposerLocationCandidate]
}

@MainActor
enum GuidedComposerTimelineInference {
    static let minimumInferenceGap =
        GuidedComposerPolicy.minimumInferenceGap

    static func makeContext(
        entries: [LogEntry],
        selectedDay: TimelineDayKey? = nil
    ) -> ComposerTimelineContext {
        let visibleEntries = if let selectedDay {
            entries.filter { isVisible($0, on: selectedDay) }
        } else {
            entries
        }
        let sortedEntries = visibleEntries.sorted {
            ($0.startTime ?? $0.endTime ?? $0.createdAt)
                < ($1.startTime ?? $1.endTime ?? $1.createdAt)
        }
        var activityCounts: [String: Int] = [:]
        let inferableWorkoutNames = sortedEntries.compactMap {
            entry -> String? in
            guard entry.entryKindReviewReason == nil,
                  let start = entry.startTime,
                  let end = entry.endTime,
                  end > start,
                  let details = entry.workoutDetails,
                  canInferWorkout(details) else {
                return nil
            }
            return details.activityName
        }
        let totalActivities = Dictionary(
            grouping: inferableWorkoutNames,
            by: GuidedComposerNormalization.text
        ).mapValues(\.count)

        var intervals: [ComposerTimelineInterval] = []
        var candidates: [ComposerLocationCandidate] = []

        for entry in sortedEntries {
            guard let startTime = entry.startTime,
                  let endTime = entry.endTime,
                  endTime > startTime,
                  entry.entryKindReviewReason == nil else {
                continue
            }

            switch entry.kind {
            case .placeVisit:
                guard let details = entry.placeVisitDetails,
                      details.review(for: .place) == nil,
                      details.review(for: .time) == nil,
                      let location = details.location
                        ?? details.place?.location else {
                    continue
                }
                let candidate = candidate(
                    entry: entry,
                    role: "visit",
                    place: details.place,
                    location: location,
                    fallbackName: details.placeRawText,
                    searchTerms: [
                        "visit",
                        details.description,
                    ].compactMap { $0 }
                )
                intervals.append(
                    ComposerTimelineInterval(
                        id: entry.id,
                        kind: .placeVisit,
                        label: details.description
                            ?? details.place?.name
                            ?? String(localized: "Visit"),
                        startTime: startTime,
                        endTime: endTime,
                        startLocation: candidate,
                        endLocation: candidate
                    )
                )
                candidates.append(candidate)

            case .transit:
                guard let details = entry.transitDetails,
                      details.review(for: .time) == nil,
                      details.review(for: .origin) == nil,
                      details.review(for: .destination) == nil,
                      let origin = details.originLocation
                        ?? details.originPlace?.location,
                      let destination = details.destinationLocation
                        ?? details.destinationPlace?.location else {
                    continue
                }
                let originCandidate = candidate(
                    entry: entry,
                    role: "transit-origin",
                    place: details.originPlace,
                    location: origin,
                    fallbackName: details.originRawText,
                    searchTerms: [
                        "\(details.type) origin",
                        "origin of \(details.type)",
                        "where \(details.type) started",
                    ]
                )
                let destinationCandidate = candidate(
                    entry: entry,
                    role: "transit-destination",
                    place: details.destinationPlace,
                    location: destination,
                    fallbackName: details.destinationRawText,
                    searchTerms: [
                        "\(details.type) destination",
                        "destination of \(details.type)",
                        "where \(details.type) ended",
                    ]
                )
                intervals.append(
                    ComposerTimelineInterval(
                        id: entry.id,
                        kind: .transit,
                        label: details.type,
                        startTime: startTime,
                        endTime: endTime,
                        startLocation: originCandidate,
                        endLocation: destinationCandidate
                    )
                )
                candidates += [originCandidate, destinationCandidate]

            case .workout:
                guard let details = entry.workoutDetails,
                      canInferWorkout(details) else {
                    continue
                }
                let key = GuidedComposerNormalization.text(details.activityName)
                activityCounts[key, default: 0] += 1
                let ordinal = activityCounts[key, default: 1]
                let total = totalActivities[key, default: 1]
                let ordinalName = "\(ordinalWord(ordinal)) \(details.activityName)"
                let lastName = ordinal == total
                    ? "last \(details.activityName)"
                    : nil

                if details.movementKind == .moving {
                    let reviewed = Set(details.fieldReviews.map(\.field))
                    guard !reviewed.contains(.origin),
                          !reviewed.contains(.destination),
                          let origin = details.originLocation
                            ?? details.originPlace?.location,
                          let destination = details.destinationLocation
                            ?? details.destinationPlace?.location else {
                        continue
                    }
                    let originCandidate = candidate(
                        entry: entry,
                        role: "workout-origin",
                        place: details.originPlace,
                        location: origin,
                        fallbackName: nil,
                        searchTerms: [
                            "\(details.activityName) origin",
                            "origin of \(details.activityName)",
                            "\(ordinalName) origin",
                            "origin of \(ordinalName)",
                            lastName.map { "\($0) origin" },
                            lastName.map { "origin of \($0)" },
                        ].compactMap { $0 }
                    )
                    let destinationCandidate = candidate(
                        entry: entry,
                        role: "workout-destination",
                        place: details.destinationPlace,
                        location: destination,
                        fallbackName: nil,
                        searchTerms: [
                            "\(details.activityName) destination",
                            "destination of \(details.activityName)",
                            "\(ordinalName) destination",
                            "destination of \(ordinalName)",
                            lastName.map { "\($0) destination" },
                            lastName.map { "destination of \($0)" },
                        ].compactMap { $0 }
                    )
                    intervals.append(
                        ComposerTimelineInterval(
                            id: entry.id,
                            kind: .workout,
                            label: ordinalName,
                            startTime: startTime,
                            endTime: endTime,
                            startLocation: originCandidate,
                            endLocation: destinationCandidate
                        )
                    )
                    candidates += [originCandidate, destinationCandidate]
                } else {
                    let reviewed = Set(details.fieldReviews.map(\.field))
                    guard !reviewed.contains(.place),
                          let location = details.sourceLocation
                            ?? details.place?.location else {
                        continue
                    }
                    let workoutCandidate = candidate(
                        entry: entry,
                        role: "workout-location",
                        place: details.place,
                        location: location,
                        fallbackName: nil,
                        searchTerms: [
                            details.activityName,
                            ordinalName,
                            lastName,
                        ].compactMap { $0 }
                    )
                    intervals.append(
                        ComposerTimelineInterval(
                            id: entry.id,
                            kind: .workout,
                            label: ordinalName,
                            startTime: startTime,
                            endTime: endTime,
                            startLocation: workoutCandidate,
                            endLocation: workoutCandidate
                        )
                    )
                    candidates.append(workoutCandidate)
                }

            case .wakeUp:
                continue
            }
        }

        intervals.sort {
            if $0.startTime == $1.startTime {
                return $0.endTime < $1.endTime
            }
            return $0.startTime < $1.startTime
        }

        let gaps = inferredGaps(in: intervals)

        return ComposerTimelineContext(
            intervals: intervals,
            gaps: gaps,
            endpointCandidates: deduplicated(candidates)
        )
    }

    static func visitMacros(
        in context: ComposerTimelineContext,
        timeZone: TimeZone
    ) -> [ComposerSuggestion] {
        var suggestions: [ComposerSuggestion] = []

        for (index, interval) in context.intervals.enumerated()
        where interval.kind == .transit || interval.kind == .workout {
            let departure = interval.startLocation
            let alreadyHasDepartureVisit =
                context.intervals[..<index].contains {
                    $0.kind == .placeVisit
                        && abs(
                            $0.endTime.timeIntervalSince(interval.startTime)
                        ) <= 60
                        && GuidedComposerLocationMatcher.sameLocation(
                            $0.endLocation,
                            departure
                        )
                }
            if hasInferenceWindow(before: index, in: context),
               !GuidedComposerLocationRanking.isHome(departure),
               !alreadyHasDepartureVisit {
                let preceding = index > 0
                    ? context.intervals[index - 1]
                    : nil
                let startBoundary = preceding.flatMap {
                    GuidedComposerLocationMatcher.sameLocation(
                        $0.endLocation,
                        departure
                    ) ? $0 : nil
                }
                let end = ComposerTimeValue(
                    date: interval.startTime,
                    timeZoneIdentifier:
                        departure.location.timeZoneIdentifier
                            ?? timeZone.identifier,
                    source: .history
                )
                let start = startBoundary.map {
                    ComposerTimeValue(
                        date: $0.endTime,
                        timeZoneIdentifier:
                            $0.endLocation.location.timeZoneIdentifier
                                ?? timeZone.identifier,
                        source: .history
                    )
                }
                let tokens = locationAndTimeTokens(
                    location: departure,
                    start: start,
                    end: end
                )
                suggestions.append(
                    ComposerSuggestion(
                        id: "visit-before-\(interval.id.uuidString)",
                        title: tokens.map(\.displayText)
                            .joined(separator: " "),
                        subtitle: startBoundary.map {
                            String(
                                localized:
                                    "Between \($0.label) and \(interval.label)"
                            )
                        } ?? String(
                            localized: "Ending before \(interval.label)"
                        ),
                        systemImage: "clock.arrow.circlepath",
                        kind: .macro(
                            tokens: tokens,
                            nextSlot: .connector
                        ),
                        score: 7_100 - index
                    )
                )
            }

            let arrival = interval.endLocation
            let alreadyHasArrivalVisit = context.intervals
                .dropFirst(index + 1)
                .contains {
                    $0.kind == .placeVisit
                        && abs(
                            $0.startTime.timeIntervalSince(interval.endTime)
                        ) <= 60
                        && GuidedComposerLocationMatcher.sameLocation(
                            $0.startLocation,
                            arrival
                        )
                }
            guard hasInferenceWindow(after: index, in: context),
                  !GuidedComposerLocationRanking.isHome(arrival),
                  !alreadyHasArrivalVisit else {
                continue
            }
            let following = index + 1 < context.intervals.count
                ? context.intervals[index + 1]
                : nil
            let endBoundary = following.flatMap {
                GuidedComposerLocationMatcher.sameLocation(
                    $0.startLocation,
                    arrival
                ) ? $0 : nil
            }
            let start = ComposerTimeValue(
                date: interval.endTime,
                timeZoneIdentifier: arrival.location.timeZoneIdentifier
                    ?? timeZone.identifier,
                source: .history
            )
            let tokens = locationAndTimeTokens(
                location: arrival,
                start: start,
                end: endBoundary.map {
                    ComposerTimeValue(
                        date: $0.startTime,
                        timeZoneIdentifier:
                            $0.startLocation.location.timeZoneIdentifier
                                ?? timeZone.identifier,
                        source: .history
                    )
                }
            )
            let subtitle: String
            if let endBoundary {
                subtitle = String(
                    localized:
                        "Between \(interval.label) and \(endBoundary.label)"
                )
            } else {
                subtitle = String(localized: "Starting after \(interval.label)")
            }
            suggestions.append(
                ComposerSuggestion(
                    id: "visit-after-\(interval.id.uuidString)",
                    title: tokens.map(\.displayText).joined(separator: " "),
                    subtitle: subtitle,
                    systemImage: "clock.arrow.circlepath",
                    kind: .macro(tokens: tokens, nextSlot: .connector),
                    score: 7_000 - index
                )
            )
        }
        return suggestions
    }

    static func hasInferenceWindow(
        before index: Int,
        in context: ComposerTimelineContext
    ) -> Bool {
        guard index > 0 else { return true }
        guard let occupiedUntil = context.intervals[..<index]
            .map(\.endTime)
            .max() else {
            return true
        }
        return context.intervals[index].startTime.timeIntervalSince(
            occupiedUntil
        ) >= minimumInferenceGap
    }

    static func hasInferenceWindow(
        after index: Int,
        in context: ComposerTimelineContext
    ) -> Bool {
        let interval = context.intervals[index]
        if context.intervals[..<index].contains(where: {
            $0.endTime > interval.endTime
        }) {
            return false
        }
        guard index + 1 < context.intervals.count else { return true }
        return context.intervals[index + 1].startTime.timeIntervalSince(
            interval.endTime
        ) >= minimumInferenceGap
    }

    static func projectedVisitSuggestions(
        from macros: [ComposerSuggestion],
        draft: ComposerDraft,
        activeSlot: ComposerSlot,
        query: String
    ) -> [ComposerSuggestion] {
        macros.compactMap { macro in
            guard let values = visitValues(in: macro) else { return nil }

            let selectedLocation = activeSlot == .location(.visit)
                ? nil
                : draft.location(.visit)
            guard selectedLocation.map({
                GuidedComposerLocationMatcher.sameLocation(
                    $0,
                    values.location
                )
            }) ?? true else {
                return nil
            }
            guard timelineTimesAreCompatible(
                draft: draft,
                values: values
            ) else {
                return nil
            }

            let tokens: [ComposerToken]
            let queryScore: Int
            let canSuggestTimelineTimes = draft.duration == nil
            switch activeSlot {
            case .connector:
                guard GuidedComposerNormalization.text(query).isEmpty else {
                    return nil
                }
                if draft.location(.visit) == nil {
                    tokens = visitTokens(
                        values,
                        includeLocationConnector: true,
                        includeTimes: canSuggestTimelineTimes,
                        hasStart: draft.time(.start) != nil,
                        hasEnd: draft.time(.end) != nil
                    )
                } else {
                    guard canSuggestTimelineTimes else { return nil }
                    tokens = visitTimeTokens(
                        values,
                        hasStart: draft.time(.start) != nil,
                        hasEnd: draft.time(.end) != nil
                    )
                }
                queryScore = 0

            case .location(.visit):
                guard let score = GuidedComposerRanking.textScore(
                    query: query,
                    candidates: values.location.allSearchTerms
                ) else {
                    return nil
                }
                tokens = visitTokens(
                    values,
                    includeLocationConnector: false,
                    includeTimes: canSuggestTimelineTimes,
                    hasStart: draft.time(.start) != nil,
                    hasEnd: draft.time(.end) != nil
                )
                queryScore = score

            case .time(.start):
                guard canSuggestTimelineTimes,
                      draft.time(.start) == nil else {
                    return nil
                }
                guard let start = values.start else { return nil }
                var timeTokens = [
                    timeToken(start, role: .start),
                ]
                if draft.time(.end) == nil, let end = values.end {
                    timeTokens += [
                        connectorToken(.to),
                        timeToken(end, role: .end),
                    ]
                }
                if draft.location(.visit) == nil {
                    timeTokens += [
                        connectorToken(.at),
                        ComposerToken(
                            displayText: values.location.displayName,
                            value: .location(values.location, .visit)
                        ),
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
                guard canSuggestTimelineTimes,
                      draft.time(.end) == nil else {
                    return nil
                }
                guard let end = values.end else { return nil }
                var timeTokens = [
                    timeToken(end, role: .end),
                ]
                if draft.time(.start) == nil, let start = values.start {
                    timeTokens += [
                        connectorToken(.from),
                        timeToken(start, role: .start),
                    ]
                }
                if draft.location(.visit) == nil {
                    timeTokens += [
                        connectorToken(.at),
                        ComposerToken(
                            displayText: values.location.displayName,
                            value: .location(values.location, .visit)
                        ),
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

            case .leading, .duration, .person,
                 .location(.origin), .location(.destination):
                return nil
            }

            guard !tokens.isEmpty else { return nil }
            return ComposerSuggestion(
                id: "\(macro.id)-projected-\(activeSlot)",
                title: tokens.map(\.displayText).joined(separator: " "),
                subtitle: macro.subtitle,
                systemImage: macro.systemImage,
                kind: .macro(tokens: tokens, nextSlot: .connector),
                score: macro.score + 30_000 + queryScore
            )
        }
    }

    private static func timelineTimesAreCompatible(
        draft: ComposerDraft,
        values: VisitValues
    ) -> Bool {
        if draft.time(.start) != nil,
           let selectedStart = draft.startTime?.date {
            guard let inferredStart = values.start?.date,
                  abs(
                      selectedStart.timeIntervalSince(inferredStart)
                  ) <= 60 else {
                return false
            }
        }
        if draft.time(.end) != nil,
           let selectedEnd = draft.endTime?.date {
            guard let inferredEnd = values.end?.date,
                  abs(
                      selectedEnd.timeIntervalSince(inferredEnd)
                  ) <= 60 else {
                return false
            }
        }
        return true
    }

    private static func isVisible(
        _ entry: LogEntry,
        on day: TimelineDayKey
    ) -> Bool {
        guard let start = entry.startTime,
              let end = entry.endTime,
              end > start else {
            return false
        }
        let zoneIdentifiers = [
            entry.startTimeZoneIdentifier,
            entry.endTimeZoneIdentifier,
            entry.creationTimeZoneIdentifier,
        ]
        let zones = zoneIdentifiers.compactMap(TimeZone.init(identifier:))
        return zones.contains { zone in
            guard let dayInterval = day.dateInterval(in: zone) else {
                return false
            }
            return start < dayInterval.end && end > dayInterval.start
        }
    }

    private static func canInferWorkout(
        _ details: WorkoutDetails
    ) -> Bool {
        let reviewed = Set(details.fieldReviews.map(\.field))
        if details.movementKind == .moving {
            return !reviewed.contains(.origin)
                && !reviewed.contains(.destination)
                && (
                    details.originLocation
                        ?? details.originPlace?.location
                ) != nil
                && (
                    details.destinationLocation
                        ?? details.destinationPlace?.location
                ) != nil
        }
        return !reviewed.contains(.place)
            && (
                details.sourceLocation
                    ?? details.place?.location
            ) != nil
    }

    static func routeGapMacros(
        in context: ComposerTimelineContext,
        timeZone: TimeZone
    ) -> [ComposerSuggestion] {
        context.gaps.enumerated().map { index, gap in
            let originZone = TimeZone(
                identifier: gap.origin.location.timeZoneIdentifier
                    ?? timeZone.identifier
            ) ?? timeZone
            let destinationZone = TimeZone(
                identifier: gap.destination.location.timeZoneIdentifier
                    ?? timeZone.identifier
            ) ?? timeZone
            let tokens = routeTokens(
                origin: gap.origin,
                start: ComposerTimeValue(
                    date: gap.startTime,
                    timeZoneIdentifier: originZone.identifier,
                    source: .history
                ),
                destination: gap.destination,
                end: ComposerTimeValue(
                    date: gap.endTime,
                    timeZoneIdentifier: destinationZone.identifier,
                    source: .history
                )
            )
            return ComposerSuggestion(
                id: "route-gap-\(gap.id)",
                title: tokens.map(\.displayText).joined(separator: " "),
                subtitle: String(
                    localized: "Fill the gap between \(gap.previous.label) and \(gap.next.label)"
                ),
                systemImage: "arrow.triangle.swap",
                kind: .macro(tokens: tokens, nextSlot: .connector),
                score: 9_000 - index
            )
        }
    }

    static func shouldOfferLeadingHomeRoute(
        in context: ComposerTimelineContext
    ) -> Bool {
        guard let first = context.intervals.first else { return false }
        return first.kind != .transit
            || !GuidedComposerLocationRanking.isHome(first.startLocation)
    }

    static func shouldOfferTrailingHomeRoute(
        in context: ComposerTimelineContext
    ) -> Bool {
        guard let last = context.intervals.last else { return false }
        return last.kind != .transit
            || !GuidedComposerLocationRanking.isHome(last.endLocation)
    }

    static func routeTokens(
        origin: ComposerLocationCandidate,
        start: ComposerTimeValue,
        destination: ComposerLocationCandidate,
        end: ComposerTimeValue
    ) -> [ComposerToken] {
        let originZone = TimeZone(
            identifier: start.timeZoneIdentifier
        ) ?? .current
        let destinationZone = TimeZone(
            identifier: end.timeZoneIdentifier
        ) ?? .current
        return [
            ComposerToken(
                displayText: "from",
                value: .connector(.from)
            ),
            ComposerToken(
                displayText: origin.displayName,
                value: .location(origin, .origin)
            ),
            ComposerToken(displayText: "at", value: .connector(.at)),
            ComposerToken(
                displayText: GuidedComposerTimeParser.displayTime(
                    start.date,
                    timeZone: originZone
                ),
                value: .time(start, .start)
            ),
            ComposerToken(displayText: "to", value: .connector(.to)),
            ComposerToken(
                displayText: destination.displayName,
                value: .location(destination, .destination)
            ),
            ComposerToken(displayText: "at", value: .connector(.at)),
            ComposerToken(
                displayText: GuidedComposerTimeParser.displayTime(
                    end.date,
                    timeZone: destinationZone
                ),
                value: .time(end, .end)
            ),
        ]
    }

    private static func locationAndTimeTokens(
        location: ComposerLocationCandidate,
        start: ComposerTimeValue?,
        end: ComposerTimeValue?
    ) -> [ComposerToken] {
        var tokens = [
            ComposerToken(displayText: "at", value: .connector(.at)),
            ComposerToken(
                displayText: location.displayName,
                value: .location(location, .visit)
            ),
        ]
        if let start {
            tokens.append(
                ComposerToken(
                    displayText: "from",
                    value: .connector(.from)
                )
            )
            tokens.append(timeToken(start, role: .start))
        }
        if let end {
            tokens.append(
                ComposerToken(displayText: "to", value: .connector(.to))
            )
            tokens.append(timeToken(end, role: .end))
        }
        return tokens
    }

    private static func visitTokens(
        _ values: VisitValues,
        includeLocationConnector: Bool,
        includeTimes: Bool,
        hasStart: Bool,
        hasEnd: Bool
    ) -> [ComposerToken] {
        var tokens: [ComposerToken] = []
        if includeLocationConnector {
            tokens.append(connectorToken(.at))
        }
        tokens.append(
            ComposerToken(
                displayText: values.location.displayName,
                value: .location(values.location, .visit)
            )
        )
        if includeTimes {
            tokens += visitTimeTokens(
                values,
                hasStart: hasStart,
                hasEnd: hasEnd
            )
        }
        return tokens
    }

    private static func visitTimeTokens(
        _ values: VisitValues,
        hasStart: Bool,
        hasEnd: Bool
    ) -> [ComposerToken] {
        var tokens: [ComposerToken] = []
        if !hasStart, let start = values.start {
            tokens += [
                connectorToken(.from),
                timeToken(start, role: .start),
            ]
        }
        if !hasEnd, let end = values.end {
            tokens += [
                connectorToken(.to),
                timeToken(end, role: .end),
            ]
        }
        return tokens
    }

    private static func connectorToken(
        _ connector: ComposerConnector
    ) -> ComposerToken {
        ComposerTokenFactory.connector(connector)
    }

    private static func timeToken(
        _ value: ComposerTimeValue,
        role: ComposerTimeRole
    ) -> ComposerToken {
        ComposerTokenFactory.time(value, role: role)
    }

    private static func visitValues(
        in suggestion: ComposerSuggestion
    ) -> VisitValues? {
        guard case .macro(let tokens, _) = suggestion.kind,
              let location = tokens.compactMap({
                  token -> ComposerLocationCandidate? in
                  guard case .location(let value, .visit) = token.value else {
                      return nil
                  }
                  return value
              }).first else {
            return nil
        }
        let start = tokens.compactMap({
            token -> ComposerTimeValue? in
            guard case .time(let value, .start) = token.value else {
                return nil
            }
            return value
        }).first
        let end = tokens.compactMap({
            token -> ComposerTimeValue? in
            guard case .time(let value, .end) = token.value else {
                return nil
            }
            return value
        }).first
        return VisitValues(
            location: location,
            start: start,
            end: end
        )
    }

    private struct VisitValues {
        let location: ComposerLocationCandidate
        let start: ComposerTimeValue?
        let end: ComposerTimeValue?
    }

    private static func candidate(
        entry: LogEntry,
        role: String,
        place: Place?,
        location: Location,
        fallbackName: String?,
        searchTerms: [String]
    ) -> ComposerLocationCandidate {
        let displayName = place?.name
            ?? location.preferredName
            ?? fallbackName
            ?? String(localized: "Location")
        return ComposerLocationCandidate(
            id: "timeline-\(entry.id.uuidString)-\(role)",
            savedPlaceID: place?.id,
            displayName: displayName,
            aliases: place?.aliases ?? [],
            location: location.withFallbackDisplayName(displayName),
            systemImage: place?.systemImage ?? .mappin,
            accuracyRadiusMeters: place?.accuracyRadiusMeters ?? 0,
            source: .timeline,
            searchTerms: searchTerms
        )
    }

    private static func containsBridgingTransit(
        from origin: ComposerLocationCandidate,
        to destination: ComposerLocationCandidate,
        start: Date,
        end: Date,
        intervals: [ComposerTimelineInterval]
    ) -> Bool {
        intervals.contains { interval in
            interval.kind == .transit
                && interval.startTime >= start.addingTimeInterval(-60)
                && interval.endTime <= end.addingTimeInterval(60)
                && GuidedComposerLocationMatcher.sameLocation(
                    interval.startLocation,
                    origin
                )
                && GuidedComposerLocationMatcher.sameLocation(
                    interval.endLocation,
                    destination
                )
        }
    }

    private static func deduplicated(
        _ candidates: [ComposerLocationCandidate]
    ) -> [ComposerLocationCandidate] {
        var result: [ComposerLocationCandidate] = []
        for candidate in candidates {
            if let index = result.firstIndex(where: {
                GuidedComposerLocationMatcher.sameLocation(
                    $0,
                    candidate
                )
                    && GuidedComposerNormalization.text($0.displayName)
                        == GuidedComposerNormalization.text(
                            candidate.displayName
                        )
            }) {
                let existing = result[index]
                result[index] = ComposerLocationCandidate(
                    id: existing.id,
                    savedPlaceID: existing.savedPlaceID
                        ?? candidate.savedPlaceID,
                    displayName: existing.displayName,
                    aliases: Array(
                        Set(existing.aliases + candidate.aliases)
                    ).sorted(),
                    location: existing.location,
                    systemImage: existing.systemImage,
                    accuracyRadiusMeters: max(
                        existing.accuracyRadiusMeters,
                        candidate.accuracyRadiusMeters
                    ),
                    usageCount: max(
                        existing.usageCount,
                        candidate.usageCount
                    ),
                    lastVisitedAt: [
                        existing.lastVisitedAt,
                        candidate.lastVisitedAt,
                    ].compactMap { $0 }.max(),
                    source: existing.source,
                    searchTerms: Array(
                        Set(
                            existing.searchTerms
                                + candidate.searchTerms
                                + candidate.allSearchTerms
                        )
                    ).sorted()
                )
            } else {
                result.append(candidate)
            }
        }
        return result
    }

    private static func inferredGaps(
        in intervals: [ComposerTimelineInterval]
    ) -> [ComposerTimelineGap] {
        var result: [ComposerTimelineGap] = []
        for nextIndex in intervals.indices where nextIndex > 0 {
            let next = intervals[nextIndex]
            let earlier = intervals[..<nextIndex]
            guard let previous = earlier.max(by: {
                if $0.endTime == $1.endTime {
                    return $0.startTime < $1.startTime
                }
                return $0.endTime < $1.endTime
            }),
            next.startTime.timeIntervalSince(previous.endTime)
                >= minimumInferenceGap,
            !GuidedComposerLocationMatcher.sameLocation(
                previous.endLocation,
                next.startLocation
            ),
            !containsBridgingTransit(
                from: previous.endLocation,
                to: next.startLocation,
                start: previous.endTime,
                end: next.startTime,
                intervals: intervals
            ) else {
                continue
            }
            result.append(
                ComposerTimelineGap(previous: previous, next: next)
            )
        }
        return result
    }

    private static func ordinalWord(_ value: Int) -> String {
        switch value {
        case 1: "first"
        case 2: "second"
        case 3: "third"
        default: "\(value)th"
        }
    }
}
