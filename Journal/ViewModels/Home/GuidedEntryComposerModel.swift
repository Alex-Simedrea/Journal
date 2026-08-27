import CoreLocation
import Foundation
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class GuidedEntryComposerModel {
    var editorText = AttributedString()
    var selection = AttributedTextSelection()
    private(set) var suggestions: [ComposerSuggestion] = []
    private(set) var activeSuggestionID: String?
    private(set) var activeSlot: ComposerSlot = .leading
    private(set) var activeQuery = ""
    private(set) var draft = ComposerDraft()
    private(set) var isSaving = false
    private(set) var isSearchingPlaces = false
    private(set) var isCalculatingRoutes = false
    private(set) var activeTimePickerSeed: ComposerTimePickerSeed?
    private(set) var isSyntaxValid = false
    private(set) var locationStatusMessage: String?
    var errorMessage: String?
    var pendingPersonName: String?

    @ObservationIgnored
    private var draftsByDay: [TimelineDayKey: ComposerDraft] = [:]
    @ObservationIgnored
    private var rawDraftsByDay: [TimelineDayKey: String] = [:]
    @ObservationIgnored
    private var bindingsByDay: [
        TimelineDayKey: [ComposerSemanticBinding]
    ] = [:]
    @ObservationIgnored
    private var selectedDay = TimelineDayKey.today()
    @ObservationIgnored
    private var places: [ComposerLocationCandidate] = []
    @ObservationIgnored
    private var timelineContext = ComposerTimelineContext(
        intervals: [],
        gaps: [],
        endpointCandidates: [],
        selectedDayInterval: nil
    )
    @ObservationIgnored
    private var people: [ComposerPersonCandidate] = []
    @ObservationIgnored
    private var transitTypes: [ComposerTransitTypeCandidate] = []
    @ObservationIgnored
    private var mapCandidates: [ComposerLocationCandidate] = []
    @ObservationIgnored
    private var contextRevision = GuidedComposerContextRevision.unspecified
    @ObservationIgnored
    private var contextGeneration = 0
    @ObservationIgnored
    private let currentLocationCoordinator =
        GuidedComposerCurrentLocationCoordinator()
    @ObservationIgnored
    private var smartRouteSuggestions: [ComposerSuggestion] = []
    @ObservationIgnored
    private var mapKitDurationSuggestion: ComposerSuggestion?
    @ObservationIgnored
    private var mapKitRouteDuration: ComposerDurationValue?
    @ObservationIgnored
    private var tokenRanges: [UUID: Range<Int>] = [:]
    @ObservationIgnored
    private var activeRange = 0..<0
    @ObservationIgnored
    private var placeSearchTask: Task<Void, Never>?
    @ObservationIgnored
    private var routeSuggestionTask: Task<Void, Never>?
    @ObservationIgnored
    private var routeSuggestionGeneration = UUID()
    @ObservationIgnored
    private var activeRouteSignature: GuidedComposerRouteWorkSignature?
    @ObservationIgnored
    private var placeSearchGeneration = UUID()
    @ObservationIgnored
    private let routeDurationCache = GuidedComposerRouteDurationCache()
    @ObservationIgnored
    private var isRendering = false
    @ObservationIgnored
    private var rawEditorString = ""
    @ObservationIgnored
    private var semanticTokenMemory: [ComposerToken] = []
    @ObservationIgnored
    private var semanticBindings: [ComposerSemanticBinding] = []
    @ObservationIgnored
    private var continuationContext: ComposerContinuationContext?
    @ObservationIgnored
    private var parseAlternatives: [ComposerParseAlternative] = []
    @ObservationIgnored
    private var lastRenderedSelectionRange: Range<Int>?
    @ObservationIgnored
    private var suggestionReplacementRanges: [String: Range<Int>] = [:]
    @ObservationIgnored
    private var pendingPersonReplacementRange: Range<Int>?
    @ObservationIgnored
    private var activeSuggestionWasExplicitlySelected = false

    var canSubmit: Bool {
        draft.canSubmit
            && isSyntaxValid
            && !isSaving
    }

    var accessibilityValue: String {
        let resolved = draft.tokens.map { token in
            "\(token.displayText), \(accessibilityRole(token.role))"
        }
        let fragment = activeQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let activeRangeIsResolvedToken = tokenRanges.values.contains(
            activeRange
        )
        return (resolved + (
            fragment.isEmpty || activeRangeIsResolvedToken
                ? []
                : ["\(fragment), unresolved"]
        )).joined(separator: "; ")
    }

    var isIdle: Bool {
        rawEditorString.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    var shouldPresentSuggestions: Bool {
        (
            !suggestions.isEmpty
                || isSearchingPlaces
                || isCalculatingRoutes
                || locationStatusMessage != nil
        ) && !isIdle
    }

    var isShowingError: Bool {
        get { errorMessage != nil }
        set {
            if !newValue {
                errorMessage = nil
            }
        }
    }

    func prepare(
        selectedDay newSelectedDay: TimelineDayKey,
        places storedPlaces: [Place],
        people storedPeople: [Person],
        transitTypes storedTransitTypes: [TransitType],
        contextRevision newContextRevision:
            GuidedComposerContextRevision? = nil,
        modelContext: ModelContext
    ) {
        let newContextRevision =
            newContextRevision ?? GuidedComposerContextRevision.unspecified
        draftsByDay[selectedDay] = draft
        rawDraftsByDay[selectedDay] = rawEditorString
        bindingsByDay[selectedDay] = semanticBindings
        selectedDay = newSelectedDay
        if newContextRevision == .unspecified
            || contextRevision != newContextRevision {
            contextGeneration &+= 1
        }
        contextRevision = newContextRevision

        let statistics = (try? PlaceVisitStatisticsService.fetch(
            in: modelContext
        )) ?? [:]
        places = storedPlaces.map { place in
            let stats = statistics[place.id]
            return ComposerLocationCandidate(
                id: "saved-\(place.id.uuidString)",
                savedPlaceID: place.id,
                displayName: place.name,
                aliases: place.aliases,
                location: place.location.withFallbackDisplayName(place.name),
                systemImage: place.systemImage,
                accuracyRadiusMeters: place.accuracyRadiusMeters,
                usageCount: stats?.visitCount ?? 0,
                lastVisitedAt: stats?.lastVisitedAt,
                source: .savedPlace
            )
        }
        let allEntries = (try? modelContext.fetch(
            FetchDescriptor<LogEntry>()
        )) ?? []
        let usageCounts = EntryDetailPeopleUsage.counts(in: allEntries)
        people = storedPeople.map {
            ComposerPersonCandidate(
                id: $0.id,
                name: $0.name,
                aliases: $0.aliases,
                contactIdentifier: $0.contactIdentifier,
                usageCount: usageCounts[$0.id, default: 0]
            )
        }
        transitTypes = storedTransitTypes.map {
            ComposerTransitTypeCandidate(
                canonicalName: $0.canonicalName,
                aliases: $0.aliases,
                routingMode: $0.routingMode
            )
        }
        let historyEntries = (try? EntryHistoryService.entries(
            around: selectedDay,
            in: modelContext
        )) ?? []
        timelineContext = GuidedComposerTimelineInference.makeContext(
            entries: historyEntries,
            selectedDay: selectedDay
        )

        draft = draftsByDay[selectedDay] ?? ComposerDraft()
        rawEditorString = rawDraftsByDay[selectedDay] ?? draft.rawSentence
        semanticTokenMemory = draft.tokens
        semanticBindings = bindingsByDay[selectedDay] ?? []
        lastRenderedSelectionRange = nil
        activeTimePickerSeed = nil
        mapCandidates = []
        if selectedDay != .today() {
            currentLocationCoordinator.cancelAndClear()
            locationStatusMessage = nil
        }
        reparseEditorText(rawEditorString, preferredSelectionOffset: nil)
    }

    func appBecameActive() {
        currentLocationCoordinator.appBecameActive(
            isNeeded: needsCurrentLocation,
            isToday: selectedDay == .today(),
            onChange: currentLocationDidChange
        )
    }

    func editorTextDidChange() {
        guard !isRendering else { return }
        let newText = String(editorText.characters)
        guard newText != rawEditorString else { return }

        if newText.contains(where: \.isNewline) {
            if let suggestion = suggestions.first {
                accept(suggestion)
            } else {
                render()
            }
            return
        }

        let selectionSnapshot = captureSelection()
        let preferredOffset = selectionSnapshot?.upperBound
        semanticBindings = GuidedComposerBindingReconciler.reconciled(
            semanticBindings,
            oldText: rawEditorString,
            newText: newText
        )
        reparseEditorText(
            newText,
            preferredSelectionOffset: preferredOffset,
            selectionSnapshot: selectionSnapshot
        )
    }

    func selectionDidChange() {
        guard !isRendering else { return }
        guard var selectionSnapshot = captureSelection() else { return }

        let selectionWasRendered = selectionSnapshot.range
            == lastRenderedSelectionRange
        var selectedWholeToken = false
        if !selectionWasRendered,
           selectionSnapshot.range.isEmpty,
           let tokenRange = tokenRange(
               containing: selectionSnapshot.range.lowerBound
           ) {
            selectionSnapshot = ComposerSelectionSnapshot(range: tokenRange)
            lastRenderedSelectionRange = tokenRange
            selectedWholeToken = true
            restoreSelection(selectionSnapshot, in: editorText)
        } else {
            lastRenderedSelectionRange = selectionSnapshot.range
        }

        applyParseSnapshot(
            parseSnapshot(
                text: rawEditorString,
                selection: selectionSnapshot.range
            )
        )
        if selectedWholeToken {
            activeQuery = ""
        }
        activeSuggestionWasExplicitlySelected = false
        updateCurrentLocationNeed()
        schedulePlaceSearchIfNeeded()
        scheduleRouteSuggestions()
        refreshSuggestions()
    }

    func editorFocusDidChange(_ isFocused: Bool) {
        guard !isFocused else { return }
        saveCurrentDraft()
    }

    func acceptTopSuggestion() {
        let suggestion = activeSuggestionID.flatMap { activeID in
            suggestions.first { $0.id == activeID }
        } ?? suggestions.first
        guard let suggestion else { return }
        accept(suggestion)
    }

    func activateSuggestion(_ suggestionID: String) {
        guard activeSuggestionID != suggestionID,
              suggestions.contains(where: { $0.id == suggestionID }) else {
            return
        }
        activeSuggestionID = suggestionID
        activeSuggestionWasExplicitlySelected = true
    }

    func activateFirstSuggestion() {
        activeSuggestionID = suggestions.first?.id
        activeSuggestionWasExplicitlySelected = false
    }

    func accept(_ suggestion: ComposerSuggestion) {
        switch suggestion.kind {
        case .addPerson(let name):
            pendingPersonReplacementRange =
                suggestionReplacementRanges[suggestion.id]
            pendingPersonName = name
            return
        case .semanticSplit(let bindings, _):
            semanticBindings = GuidedComposerBindingReconciler.merged(
                semanticBindings + bindings
            )
            let connectorEndsSentence = bindings.contains {
                $0.range.upperBound == rawEditorString.count
                    && $0.token.role == .connector
            }
            let updatedText = connectorEndsSentence
                ? rawEditorString + " "
                : rawEditorString
            reparseEditorText(
                updatedText,
                preferredSelectionOffset: connectorEndsSentence
                    ? updatedText.count
                    : captureSelection()?.upperBound
            )
            return
        case .value(let tokens, let nextSlot),
             .macro(let tokens, let nextSlot):
            acceptTokens(
                tokens,
                nextSlot: nextSlot,
                replacing: suggestionReplacementRanges[suggestion.id]
            )
            return
        }
    }

    func selectTime(_ date: Date, role: ComposerTimeRole) {
        let zone = activeTimeZone(for: role)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let minuteComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        var resolvedDate = calendar.date(from: minuteComponents) ?? date
        if role == .end, let start = draft.startTime?.date {
            resolvedDate = GuidedComposerTimeParser.rolledEndIfNeeded(
                resolvedDate,
                after: start,
                hadExplicitDate: false,
                timeZone: zone
            )
        }
        accept(
            ComposerSuggestion(
                id: "picker-time-\(resolvedDate.timeIntervalSince1970)",
                title: GuidedComposerTimeParser.displayTime(
                    resolvedDate,
                    timeZone: zone
                ),
                subtitle: nil,
                systemImage: "clock",
                kind: .value(
                    tokens: [
                        ComposerToken(
                            displayText:
                                GuidedComposerTimeParser.displayTime(
                                    resolvedDate,
                                    timeZone: zone
                                ),
                            value: .time(
                                ComposerTimeValue(
                                    date: resolvedDate,
                                    timeZoneIdentifier: zone.identifier,
                                    source: .explicit
                                ),
                                role
                            )
                        ),
                    ],
                    nextSlot: .connector
                ),
                score: 10_000
            )
        )
    }

    func suggestedPickerDate(
        for role: ComposerTimeRole,
        now: Date = .now
    ) -> Date {
        if let activeTimePickerSeed,
           activeTimePickerSeed.role == role {
            return activeTimePickerSeed.date
        }
        return defaultPickerTime(
            zone: activeTimeZone(for: role),
            now: now
        )
    }

    func pickerTimeZone(for role: ComposerTimeRole) -> TimeZone {
        if let activeTimePickerSeed,
           activeTimePickerSeed.role == role {
            return TimeZone(
                identifier: activeTimePickerSeed.timeZoneIdentifier
            ) ?? activeTimeZone(for: role)
        }
        return activeTimeZone(for: role)
    }

    func pickerSeedID(for role: ComposerTimeRole) -> UUID? {
        guard activeTimePickerSeed?.role == role else { return nil }
        return activeTimePickerSeed?.id
    }

    func pickerContextID(for role: ComposerTimeRole) -> String {
        let oppositeBoundary = role == .end
            ? draft.startTime?.date
            : draft.endTime?.date
        return [
            "\(selectedDay.year)-\(selectedDay.month)-\(selectedDay.day)",
            role.rawValue,
            pickerSeedID(for: role)?.uuidString ?? "unseeded",
            oppositeBoundary.map {
                String(Int($0.timeIntervalSince1970.rounded()))
            } ?? "no-opposite-boundary",
            pickerTimeZone(for: role).identifier,
        ].joined(separator: ":")
    }

    func personWasAdded(_ person: Person) {
        pendingPersonName = nil
        let replacementRange = pendingPersonReplacementRange
        pendingPersonReplacementRange = nil
        let candidate = ComposerPersonCandidate(
            id: person.id,
            name: person.name,
            aliases: person.aliases,
            contactIdentifier: person.contactIdentifier,
            usageCount: 0
        )
        if !people.contains(where: { $0.id == candidate.id }) {
            people.append(candidate)
        }
        let suggestion = personSuggestion(candidate, score: 10_000)
        guard case .value(let tokens, let nextSlot) = suggestion.kind else {
            return
        }
        acceptTokens(
            tokens,
            nextSlot: nextSlot,
            replacing: replacementRange
        )
    }

    func cancelPendingPersonAddition() {
        pendingPersonName = nil
        pendingPersonReplacementRange = nil
    }

    func submit(
        places storedPlaces: [Place],
        people storedPeople: [Person],
        modelContext: ModelContext
    ) -> Bool {
        guard canSubmit, let kind = draft.entryKind,
              let start = draft.startTime,
              let end = draft.endTime else {
            return false
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let selectedPeople = storedPeople.filter { person in
            draft.people.contains(where: { $0.id == person.id })
        }
        let rawInput = rawEditorString.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        do {
            let entry: LogEntry
            switch kind {
            case .placeVisit(let description):
                guard let location = draft.location(.visit) else {
                    return false
                }
                let place = storedPlaces.first {
                    $0.id == location.savedPlaceID
                }
                entry = try PlaceVisitEntryStore.insert(
                    draft: ResolvedPlaceVisitDraft(
                        description: description,
                        place: place,
                        location: location.location,
                        placeRawText: location.displayName,
                        startTime: start.date,
                        endTime: end.date,
                        timeConfidence: draft.timeConfidence,
                        people: selectedPeople,
                        candidates: [],
                        unresolvedPeople: [],
                        fieldReviews: [],
                        entryKindReviewReason: nil
                    ),
                    rawInput: rawInput,
                    in: modelContext
                )

            case .transit(let canonicalName):
                guard let origin = draft.location(.origin),
                      let destination = draft.location(.destination) else {
                    return false
                }
                let originPlace = storedPlaces.first {
                    $0.id == origin.savedPlaceID
                }
                let destinationPlace = storedPlaces.first {
                    $0.id == destination.savedPlaceID
                }
                entry = try TransitEntryStore.insert(
                    draft: ResolvedTransitDraft(
                        transitType: canonicalName,
                        originPlace: originPlace,
                        originLocation: origin.location,
                        originRawText: origin.displayName,
                        destinationPlace: destinationPlace,
                        destinationLocation: destination.location,
                        destinationRawText: destination.displayName,
                        startTime: start.date,
                        endTime: end.date,
                        timeConfidence: draft.timeConfidence,
                        people: selectedPeople,
                        durationSource: draft.durationSource,
                        originCandidates: [],
                        destinationCandidates: [],
                        unresolvedPeople: [],
                        fieldReviews: []
                    ),
                    rawInput: rawInput,
                    in: modelContext
                )
            }

            EntryWeatherService.refreshInBackground(
                entry,
                in: modelContext
            )
            clearCurrentDraft()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clearCurrentDraft() {
        placeSearchTask?.cancel()
        placeSearchGeneration = UUID()
        placeSearchTask = nil
        isSearchingPlaces = false
        draft = ComposerDraft()
        draftsByDay[selectedDay] = draft
        rawEditorString = ""
        rawDraftsByDay[selectedDay] = ""
        semanticTokenMemory = []
        semanticBindings = []
        bindingsByDay[selectedDay] = []
        activeSlot = .leading
        activeQuery = ""
        activeTimePickerSeed = nil
        isSyntaxValid = false
        mapCandidates = []
        continuationContext = nil
        parseAlternatives = []
        tokenRanges = [:]
        lastRenderedSelectionRange = nil
        suggestionReplacementRanges = [:]
        pendingPersonReplacementRange = nil
        scheduleRouteSuggestions()
        refreshSuggestions()
        render()
    }

    private func refreshSuggestions() {
        suggestionReplacementRanges = [:]
        var values: [ComposerSuggestion] = switch activeSlot {
        case .leading:
            leadingSuggestions()
        case .connector:
            connectorSuggestions()
        case .location(let role):
            locationSuggestions(role: role)
        case .time(let role):
            timeSuggestions(role: role)
        case .duration:
            durationSuggestions()
        case .person:
            personSuggestions()
                + (
                    activeQuery.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                        && tokenBeforeActiveRange()?.role == .person
                        ? connectorSuggestions()
                        : []
                )
        }
        if let continuationContext {
            let continuationSuggestions: [ComposerSuggestion]
            switch continuationContext.slot {
            case .leading:
                continuationSuggestions = leadingSuggestions(
                    queryOverride: continuationContext.query
                )
            case .location(let role):
                continuationSuggestions = locationSuggestions(
                    role: role,
                    queryOverride: continuationContext.query
                )
            case .person:
                continuationSuggestions = personSuggestions(
                    queryOverride: continuationContext.query
                )
            case .time, .duration, .connector:
                continuationSuggestions = []
            }
            values += targetedSuggestions(
                continuationSuggestions,
                replacing: continuationContext.range
            )
        }
        values += smartContextualSuggestions()
        values += parseAlternatives.map {
            ComposerSuggestion(
                id: $0.id,
                title: $0.title,
                subtitle: $0.subtitle,
                systemImage: $0.systemImage,
                kind: .semanticSplit(
                    bindings: $0.bindings,
                    nextSlot: $0.nextSlot
                ),
                score: $0.score
            )
        }
        suggestions = GuidedComposerSuggestionDeduplicator.deduplicated(values)
        suggestions.sort {
            if $0.score == $1.score {
                let titleOrder = $0.title.localizedStandardCompare($1.title)
                if titleOrder == .orderedSame {
                    return $0.id < $1.id
                }
                return titleOrder == .orderedAscending
            }
            return $0.score > $1.score
        }
        if !activeSuggestionWasExplicitlySelected
            || !suggestions.contains(where: { $0.id == activeSuggestionID }) {
            activeSuggestionID = suggestions.first?.id
            activeSuggestionWasExplicitlySelected = false
        }
    }

    private func targetedSuggestions(
        _ suggestions: [ComposerSuggestion],
        replacing range: Range<Int>
    ) -> [ComposerSuggestion] {
        suggestions.map { suggestion in
            let targetedID = [
                "replace",
                "\(range.lowerBound)-\(range.upperBound)",
                suggestion.id,
            ].joined(separator: "-")
            suggestionReplacementRanges[targetedID] = range
            return ComposerSuggestion(
                id: targetedID,
                title: suggestion.title,
                subtitle: suggestion.subtitle,
                systemImage: suggestion.systemImage,
                kind: suggestion.kind,
                score: suggestion.score
            )
        }
    }

    private func leadingSuggestions(
        queryOverride: String? = nil
    ) -> [ComposerSuggestion] {
        let query = (queryOverride ?? activeQuery).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let normalizedQuery = GuidedComposerNormalization.text(query)
        let queryIsRideShare = GuidedComposerTransitFamily
            .isRideShareSearchTerm(normalizedQuery)
        var values: [ComposerSuggestion] = transitTypes.compactMap { type in
            let directScore = GuidedComposerRanking.textScore(
                query: query,
                candidates: [type.canonicalName] + type.aliases
            )
            let familyScore = queryIsRideShare
                    && GuidedComposerTransitFamily
                        .isRideShareSearchTerm(type.canonicalName)
                ? 4_500
                : nil
            guard let score = directScore ?? familyScore else {
                return nil
            }
            let isExactAlias = ([type.canonicalName] + type.aliases).contains {
                GuidedComposerNormalization.text($0)
                    == GuidedComposerNormalization.text(query)
            }
            let displayText = isExactAlias && !query.isEmpty
                ? query
                : type.canonicalName
            return ComposerSuggestion(
                id: "type-\(type.canonicalName)",
                title: displayText,
                subtitle: type.canonicalName,
                systemImage: TransitPresentationCatalog.presentation(
                    for: type.canonicalName
                ).systemImageName,
                kind: .value(
                    tokens: [
                        ComposerToken(
                            displayText: displayText,
                            value: .leading(
                                .transit(
                                    canonicalName: type.canonicalName
                                )
                            )
                        ),
                    ],
                    nextSlot: .connector
                ),
                score: score + relatedTransitBonus(type.canonicalName)
            )
        }
        if query.isEmpty
            || GuidedComposerRanking.textScore(
                query: query,
                candidates: ["Stay"]
            ) != nil {
            values.append(
                ComposerSuggestion(
                    id: "type-stay",
                    title: "Stay",
                    subtitle: String(localized: "Place visit"),
                    systemImage: "mappin.and.ellipse",
                    kind: .value(
                        tokens: [
                            ComposerToken(
                                displayText:
                                    normalizedQuery == "stay"
                                    ? query
                                    : "Stay",
                                value: .leading(
                                    .placeVisit(description: nil)
                                )
                            ),
                        ],
                        nextSlot: .connector
                    ),
                    score: query.isEmpty ? 9_000 : 8_500
                )
            )
        }
        if !query.isEmpty,
           GuidedComposerNormalization.text(query) != "stay",
           !values.contains(where: {
               GuidedComposerNormalization.text($0.title)
                   == GuidedComposerNormalization.text(query)
           }) {
            values.append(
                ComposerSuggestion(
                    id: "description-\(query)",
                    title: String(localized: "Use “\(query)”"),
                    subtitle: String(localized: "Place visit description"),
                    systemImage: "text.quote",
                    kind: .value(
                        tokens: [
                            ComposerToken(
                                displayText: query,
                                value: .leading(
                                    .placeVisit(description: query)
                                )
                            ),
                        ],
                        nextSlot: .connector
                    ),
                    score: 3_000
                )
            )
        }
        return values
    }

    private func connectorSuggestions() -> [ComposerSuggestion] {
        guard let kind = draft.entryKind else { return [] }
        let query = activeQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let replacementOptions = activeConnectorReplacementOptions(
            entryKind: kind
        )
        let connectors = replacementOptions ?? GuidedComposerGrammar
            .legalConnectors(
                entryKind: kind,
                tokens: draft.tokens
            ).map {
                GuidedComposerConnectorOption(
                    displayText: $0.connector.rawValue,
                    connector: $0.connector,
                    slot: $0.slot
                )
            }

        let values = connectors.compactMap {
            option -> ComposerSuggestion? in
            let score: Int
            if replacementOptions != nil {
                score = GuidedComposerNormalization.text(option.displayText)
                    == GuidedComposerNormalization.text(
                        activelyEditedConnector?.displayText ?? ""
                    ) ? 11_000 : 10_000
            } else {
                guard let rankedScore = GuidedComposerRanking.textScore(
                    query: query,
                    candidates: [option.displayText]
                ) else {
                    return nil
                }
                score = rankedScore
            }
            return ComposerSuggestion(
                id:
                    "connector-\(option.displayText)-\(option.connector.rawValue)-\(option.slot)",
                title: option.displayText,
                subtitle: connectorSubtitle(option.slot),
                systemImage: connectorSystemImage(option.slot),
                kind: .value(
                    tokens: [
                        ComposerToken(
                            displayText: option.displayText,
                            value: .connector(option.connector)
                        ),
                    ],
                    nextSlot: option.slot
                ),
                score: score
                    + 1_000
                    + connectorPriority(
                        connector: option.connector,
                        nextSlot: option.slot,
                        kind: kind
                    )
            )
        }

        return values
    }

    private var activelyEditedConnector: ComposerToken? {
        draft.tokens.first {
            $0.role == .connector
                && tokenRanges[$0.id] == activeRange
        }
    }

    private func activeConnectorReplacementOptions(
        entryKind: ComposerEntryKind
    ) -> [GuidedComposerConnectorOption]? {
        guard let connector = activelyEditedConnector,
              let connectorIndex = draft.tokens.firstIndex(where: {
                  $0.id == connector.id
              }),
              draft.tokens[
                  draft.tokens.index(after: connectorIndex)...
              ].contains(where: { $0.role != .connector }) else {
            return nil
        }
        return GuidedComposerGrammar.replacementOptions(
            entryKind: entryKind,
            tokens: draft.tokens,
            connectorIndex: connectorIndex,
            currentDisplayText: connector.displayText
        )
    }

    private func smartContextualSuggestions() -> [ComposerSuggestion] {
        guard let kind = draft.entryKind else { return [] }
        switch kind {
        case .transit:
            let gapRoutes = GuidedComposerTimelineInference.routeGapMacros(
                in: timelineContext,
                timeZone: .current
            )
            var values = GuidedComposerRouteInference.projectedSuggestions(
                from: gapRoutes + smartRouteSuggestions,
                draft: draft,
                activeSlot: activeSlot,
                query: activeQuery
            )
            if let mapKitConnectorSuggestion {
                values.append(mapKitConnectorSuggestion)
            }
            return values
        case .placeVisit:
            let visitMacros = GuidedComposerTimelineInference.visitMacros(
                in: timelineContext,
                timeZone: .current
            )
            return GuidedComposerTimelineInference
                .projectedVisitSuggestions(
                    from: visitMacros,
                    draft: draft,
                    activeSlot: activeSlot,
                    query: activeQuery
                )
        }
    }

    private var mapKitConnectorSuggestion: ComposerSuggestion? {
        guard let entryKind = draft.entryKind,
              activeSlot == .connector,
              activeQuery.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty,
              draft.duration == nil else {
            return nil
        }
        let role: ComposerTimeRole
        let connector: ComposerConnector
        if draft.time(.start) != nil, draft.time(.end) == nil {
            role = .end
            connector = .to
        } else if draft.time(.end) != nil, draft.time(.start) == nil {
            role = .start
            connector = .from
        } else {
            return nil
        }
        guard GuidedComposerGrammar.legalConnectors(
            entryKind: entryKind,
            tokens: draft.tokens
        ).contains(where: {
            $0.connector == connector && $0.slot == .time(role)
        }) else {
            return nil
        }
        guard let timeSuggestion = mapKitTimeSuggestion(
            role: role,
            query: "",
            zone: activeTimeZone(for: role)
        ), case .value(let timeTokens, _) = timeSuggestion.kind else {
            return nil
        }
        let connectorToken = ComposerToken(
            displayText: connector.rawValue,
            value: .connector(connector)
        )
        let tokens = [connectorToken] + timeTokens
        return ComposerSuggestion(
            id: "connector-\(timeSuggestion.id)",
            title: tokens.map(\.displayText).joined(separator: " "),
            subtitle: timeSuggestion.subtitle,
            systemImage: timeSuggestion.systemImage,
            kind: .macro(tokens: tokens, nextSlot: .connector),
            score: timeSuggestion.score
        )
    }

    private func connectorPriority(
        connector: ComposerConnector,
        nextSlot: ComposerSlot,
        kind: ComposerEntryKind
    ) -> Int {
        switch kind {
        case .placeVisit:
            if connector == .at, draft.location(.visit) == nil {
                return 600
            }
            if connector == .from, draft.time(.start) == nil {
                return 400
            }
        case .transit:
            if connector == .to,
               draft.location(.origin) != nil,
               draft.location(.destination) == nil {
                return 900
            }
            if connector == .from,
               draft.location(.origin) == nil {
                return draft.location(.destination) == nil ? 700 : 900
            }
            if case .location = nextSlot {
                return 500
            }
        }
        return 0
    }

    private func locationSuggestions(
        role: ComposerLocationRole,
        queryOverride: String? = nil
    ) -> [ComposerSuggestion] {
        let query = (queryOverride ?? activeQuery).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let alreadySelectedIDs = Set([
            draft.location(.visit)?.id,
            draft.location(.origin)?.id,
            draft.location(.destination)?.id,
        ].compactMap { $0 })
        let conflictingLocations: [ComposerLocationCandidate] = switch role {
        case .origin:
            [draft.location(.destination)].compactMap { $0 }
        case .destination:
            [draft.location(.origin)].compactMap { $0 }
        case .visit:
            []
        }

        let gapRoutes = GuidedComposerTimelineInference.routeGapMacros(
            in: timelineContext,
            timeZone: .current
        )
        let contextualLocations = GuidedComposerRouteInference
            .contextualLocations(
                from: gapRoutes + smartRouteSuggestions,
                draft: draft,
                role: role
            )

        var candidates = places
        if !query.isEmpty {
            for endpoint in timelineContext.endpointCandidates
            where !candidates.contains(where: {
                $0.savedPlaceID != nil
                    && $0.savedPlaceID == endpoint.savedPlaceID
            }) {
                candidates.append(endpoint)
            }
        }
        candidates += mapCandidates
        candidates = GuidedComposerLocationRanking.deduplicated(candidates)
        let otherEndpoint: ComposerLocationCandidate? = switch role {
        case .origin:
            draft.location(.destination)
        case .destination:
            draft.location(.origin)
        case .visit:
            nil
        }

        let values = candidates.compactMap {
            candidate -> ComposerSuggestion? in
            guard !alreadySelectedIDs.contains(candidate.id)
                    || draft.location(role)?.id == candidate.id,
                  draft.location(role)?.id == candidate.id
                    || !conflictingLocations.contains(where: {
                        GuidedComposerLocationMatcher.sameLocation(
                            $0,
                            candidate
                        )
                    }),
                  let baseScore = GuidedComposerLocationRanking.suggestionScore(
                      query: query,
                      candidate: candidate,
                      otherEndpoint: otherEndpoint,
                      currentLocation: currentLocation
                ) else {
                return nil
            }
            let contextualIndex = contextualLocations.firstIndex {
                GuidedComposerLocationMatcher.sameLocation(
                    $0,
                    candidate
                )
            }
            let contextualBonus = contextualIndex.map {
                15_000 - min($0 * 100, 2_000)
            } ?? 0
            let score = baseScore + contextualBonus
            return ComposerSuggestion(
                id: "location-\(role.rawValue)-\(candidate.id)",
                title: candidate.displayName,
                subtitle: candidate.location.presentationAddress,
                systemImage: candidate.systemImage.rawValue,
                kind: .value(
                    tokens: [
                        ComposerToken(
                            displayText: exactDisplayText(
                                query: query,
                                fallback: candidate.displayName,
                                terms: candidate.allSearchTerms
                            ),
                            value: .location(candidate, role)
                        ),
                    ],
                    nextSlot: .connector
                ),
                score: score
            )
        }

        return values
    }

    private func timeSuggestions(
        role: ComposerTimeRole
    ) -> [ComposerSuggestion] {
        let query = activeQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let zone = activeTimeZone(for: role)
        let now = Date.now
        var values: [ComposerSuggestion] = []
        if let mapKitSuggestion = mapKitTimeSuggestion(
            role: role,
            query: query,
            zone: zone
        ) {
            values.append(mapKitSuggestion)
        }
        if let parsed = GuidedComposerTimeParser.parseTime(
            query,
            role: role,
            selectedDay: selectedDay,
            timeZone: zone
        ) {
            var date = parsed
            if role == .end, let start = draft.startTime?.date {
                date = GuidedComposerTimeParser.rolledEndIfNeeded(
                    parsed,
                    after: start,
                    hadExplicitDate: !GuidedComposerTimeParser
                        .isUnqualifiedClock(query),
                    timeZone: zone
                )
            }
            let display = GuidedComposerTimeParser.normalizedDisplayText(
                for: query,
                resolvedDate: date,
                timeZone: zone
            )
            values.append(
                ComposerSuggestion(
                    id: "time-\(role.rawValue)-\(date.timeIntervalSince1970)",
                    title: display,
                    subtitle: GuidedComposerTimeParser.displayDateTime(
                        date,
                        timeZone: zone
                    ),
                    systemImage: "clock",
                    kind: .value(
                        tokens: [
                            ComposerTokenFactory.explicitTime(
                                date: date,
                                timeZone: zone,
                                role: role,
                                displayText: display,
                                allowsOvernightRollover:
                                    role == .end
                                    && GuidedComposerTimeParser
                                        .isUnqualifiedClock(query)
                            ),
                        ],
                        nextSlot: .connector
                    ),
                    score: 10_000
                )
            )
        }

        if selectedDay == .today(now: now, timeZone: zone) {
            values.append(
                ComposerSuggestion(
                    id: "time-now-\(role.rawValue)",
                    title: String(localized: "Now"),
                    subtitle: GuidedComposerTimeParser.displayDateTime(
                        now,
                        timeZone: zone
                    ),
                    systemImage: "clock.badge.checkmark",
                    kind: .value(
                        tokens: [
                            ComposerTokenFactory.explicitTime(
                                date: now,
                                timeZone: zone,
                                role: role,
                                displayText: String(localized: "now"),
                                allowsOvernightRollover: false
                            ),
                        ],
                        nextSlot: .connector
                    ),
                    score: query.isEmpty ? 11_000 : 500
                )
            )
        }

        if query.isEmpty {
            let oppositeBoundary = role == .end
                ? draft.time(.start)?.date
                : draft.time(.end)?.date
            let presets: [(date: Date, subtitle: String)]
            if let oppositeBoundary {
                presets = [10, 15, 30, 45, 60].map { minutes in
                    let interval = TimeInterval(minutes * 60)
                    return (
                        role == .end
                            ? oppositeBoundary.addingTimeInterval(interval)
                            : oppositeBoundary.addingTimeInterval(-interval),
                        role == .end
                            ? String(
                                localized:
                                    "\(minutes) minutes after departure"
                            )
                            : String(
                                localized:
                                    "\(minutes) minutes before arrival"
                            )
                    )
                }
            } else {
                let base = defaultPickerTime(
                    zone: zone,
                    now: now
                )
                let offsets = selectedDay == .today(
                    now: now,
                    timeZone: zone
                ) ? [15, 30, 60] : [0, 15, 30, 60]
                presets = offsets.map { offset in
                    (
                        base.addingTimeInterval(
                            TimeInterval(offset * 60)
                        ),
                        offset == 0
                            ? String(localized: "Suggested")
                            : String(localized: "\(offset) minutes later")
                    )
                }
            }
            for (index, preset) in presets.enumerated() {
                let date = preset.date
                let display = GuidedComposerTimeParser.displayTime(
                    date,
                    timeZone: zone
                )
                values.append(
                    ComposerSuggestion(
                        id: "time-preset-\(role.rawValue)-\(index)",
                        title: display,
                        subtitle: preset.subtitle,
                        systemImage: "clock",
                        kind: .value(
                            tokens: [
                                ComposerToken(
                                    displayText: display,
                                    value: .time(
                                        ComposerTimeValue(
                                            date: date,
                                            timeZoneIdentifier:
                                                zone.identifier,
                                            source: .explicit
                                        ),
                                        role
                                    )
                                ),
                            ],
                            nextSlot: .connector
                        ),
                        score: 7_000 - index
                    )
                )
            }
        }
        return values
    }

    private func mapKitTimeSuggestion(
        role: ComposerTimeRole,
        query: String,
        zone: TimeZone
    ) -> ComposerSuggestion? {
        guard draft.duration == nil,
              let mapKitRouteDuration else {
            return nil
        }
        guard (
            draft.time(role) == nil
                || isActivelyEditingToken(role: .time(role))
        ),
              let date = GuidedComposerRouteInference.derivedBoundaryTime(
                  role: role,
                  start: draft.time(.start)?.date,
                  end: draft.time(.end)?.date,
                  duration: mapKitRouteDuration.interval
              ) else {
            return nil
        }
        let display = GuidedComposerTimeParser.displayTime(
            date,
            timeZone: zone
        )
        guard let queryScore = GuidedComposerRanking.textScore(
            query: query,
            candidates: [display]
        ) else {
            return nil
        }
        return ComposerSuggestion(
            id: "time-mapkit-\(role.rawValue)-\(date.timeIntervalSince1970)",
            title: display,
            subtitle: String(
                localized:
                    "MapKit · \(GuidedComposerTimeParser.displayDuration(mapKitRouteDuration.interval))"
            ),
            systemImage: "map",
            kind: .value(
                tokens: [
                    ComposerToken(
                        displayText: display,
                        value: .time(
                            ComposerTimeValue(
                                date: date,
                                timeZoneIdentifier: zone.identifier,
                                source: .explicit,
                                durationSource: mapKitRouteDuration.source
                            ),
                            role
                        )
                    ),
                ],
                nextSlot: .connector
            ),
            score: 12_000 + queryScore
        )
    }

    private func isActivelyEditingToken(
        role: ComposerValueRole
    ) -> Bool {
        draft.tokens.contains {
            $0.role == role && tokenRanges[$0.id] == activeRange
        }
    }

    private func durationSuggestions() -> [ComposerSuggestion] {
        let query = activeQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        var durations = [10, 15, 30, 45, 60, 90, 120].map {
            TimeInterval($0 * 60)
        }
        if let parsed = GuidedComposerTimeParser.parseDuration(query),
           !durations.contains(parsed) {
            durations.insert(parsed, at: 0)
        }
        if query.allSatisfy(\.isNumber),
           let minutes = Int(query),
           minutes > 0 {
            let minuteDuration = TimeInterval(minutes * 60)
            if !durations.contains(minuteDuration) {
                durations.append(minuteDuration)
            }
        }
        var values = durations.compactMap {
            duration -> ComposerSuggestion? in
            let display = GuidedComposerTimeParser.displayDuration(duration)
            let searchTerms = durationSearchTerms(
                duration,
                display: display
            )
            guard let score = GuidedComposerRanking.textScore(
                query: query,
                candidates: searchTerms
            ) else {
                return nil
            }
            return ComposerSuggestion(
                id: "duration-\(duration)",
                title: display,
                subtitle: nil,
                systemImage: "timer",
                kind: .value(
                    tokens: [
                        ComposerToken(
                            displayText: display,
                            value: .duration(
                                ComposerDurationValue(
                                    interval: duration,
                                    source: .manualOverride
                                )
                            )
                        ),
                    ],
                    nextSlot: .connector
                ),
                score: score
            )
        }
        if query.isEmpty, let mapKitDurationSuggestion {
            values.append(mapKitDurationSuggestion)
        }
        return values
    }

    private func durationSearchTerms(
        _ duration: TimeInterval,
        display: String
    ) -> [String] {
        let totalMinutes = Int((duration / 60).rounded())
        var terms = [display, "\(totalMinutes)m"]
        if totalMinutes.isMultiple(of: 60) {
            terms.append("\(totalMinutes / 60)h")
        }
        return terms
    }

    private func personSuggestions(
        queryOverride: String? = nil
    ) -> [ComposerSuggestion] {
        let query = (queryOverride ?? activeQuery).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        var selected = Set(draft.people.map(\.id))
        if queryOverride == nil,
           let activelyEditedPersonID = draft.tokens.first(where: {
               guard case .person = $0.value,
                     let range = tokenRanges[$0.id] else {
                   return false
               }
               return range == activeRange
           }).flatMap({ token -> UUID? in
               guard case .person(let person) = token.value else {
                   return nil
               }
               return person.id
           }) {
            selected.remove(activelyEditedPersonID)
        }
        var values = people.compactMap { person -> ComposerSuggestion? in
            guard !selected.contains(person.id),
                  let textScore = GuidedComposerRanking.textScore(
                      query: query,
                      candidates: [person.name] + person.aliases
                  ) else {
                return nil
            }
            return personSuggestion(
                person,
                score: textScore + min(person.usageCount, 100) * 20,
                prefixWithListSeparator:
                    queryOverride == nil
                    && query.isEmpty
                    && tokenBeforeActiveRange()?.role == .person,
                displayText: exactDisplayText(
                    query: query,
                    fallback: person.name,
                    terms: [person.name] + person.aliases
                )
            )
        }
        if !query.isEmpty,
           !values.contains(where: {
               GuidedComposerNormalization.text($0.title)
                   == GuidedComposerNormalization.text(query)
           }) {
            values.append(
                ComposerSuggestion(
                    id: "add-person-\(query)",
                    title: String(localized: "Add “\(query)”"),
                    subtitle: String(localized: "New person"),
                    systemImage: "person.badge.plus",
                    kind: .addPerson(name: query),
                    score: 2_000
                )
            )
        }
        return values
    }

    private func personSuggestion(
        _ person: ComposerPersonCandidate,
        score: Int,
        prefixWithListSeparator: Bool = false,
        displayText: String? = nil
    ) -> ComposerSuggestion {
        let personToken = ComposerToken(
            displayText: displayText ?? person.name,
            value: .person(person)
        )
        let tokens = prefixWithListSeparator
            ? [
                ComposerToken(
                    displayText: ",",
                    value: .connector(.with)
                ),
                personToken,
            ]
            : [personToken]
        return ComposerSuggestion(
            id: "person-\(person.id.uuidString)-\(prefixWithListSeparator)",
            title: tokens.map(\.displayText).joined(separator: " "),
            subtitle: person.usageCount > 0
                ? String(localized: "Used \(person.usageCount) times")
                : nil,
            systemImage: "person.circle",
            kind: prefixWithListSeparator ? .macro(
                tokens: tokens,
                nextSlot: .person
            ) : .value(
                tokens: tokens,
                nextSlot: .person
            ),
            score: score
        )
    }

    private func acceptTokens(
        _ acceptedTokens: [ComposerToken],
        nextSlot: ComposerSlot,
        replacing replacementRange: Range<Int>? = nil
    ) {
        let replacementRange = replacementRange ?? activeRange
        var tokens = acceptedTokens
        if replacementRange.isEmpty,
           let previousToken = token(before: replacementRange.lowerBound),
           case .connector(let previousConnector) = previousToken.value,
           let firstToken = tokens.first,
           case .connector(let acceptedConnector) = firstToken.value,
           previousConnector == acceptedConnector {
            tokens.removeFirst()
        }
        guard !tokens.isEmpty else {
            activeSlot = nextSlot
            refreshSuggestions()
            return
        }

        semanticTokenMemory = GuidedComposerBindingReconciler
            .mergedTokenMemory(
                semanticTokenMemory + draft.tokens + tokens
            )
        let replacement = tokens.map(\.displayText).joined(separator: " ")
        let advancedResult = GuidedComposerTextEditor.accepting(
            replacement,
            in: rawEditorString,
            replacing: replacementRange
        )
        semanticBindings = GuidedComposerBindingReconciler.reconciled(
            semanticBindings,
            oldText: rawEditorString,
            newText: advancedResult.text
        )
        semanticBindings.removeAll {
            $0.range.overlaps(advancedResult.insertedRange)
        }
        semanticBindings += GuidedComposerBindingReconciler.bindings(
            for: tokens,
            insertedRange: advancedResult.insertedRange,
            in: advancedResult.text
        )
        semanticBindings = GuidedComposerBindingReconciler.merged(
            semanticBindings
        )
        activeSlot = nextSlot
        activeQuery = ""
        activeTimePickerSeed = nil
        mapCandidates = []
        reparseEditorText(
            advancedResult.text,
            preferredSelectionOffset: advancedResult.caretOffset
        )
    }

    private func reparseEditorText(
        _ rawText: String,
        preferredSelectionOffset: Int?,
        selectionSnapshot: ComposerSelectionSnapshot? = nil
    ) {
        activeSuggestionWasExplicitlySelected = false
        rawEditorString = rawText

        let previousTokens = draft.tokens
        semanticTokenMemory = GuidedComposerBindingReconciler
            .mergedTokenMemory(
                semanticTokenMemory + previousTokens
            )
        let snapshot = selectionSnapshot
            ?? preferredSelectionOffset.map {
                ComposerSelectionSnapshot(range: $0..<$0)
            }
            ?? ComposerSelectionSnapshot(
                range: rawText.count..<rawText.count
            )
        applyParseSnapshot(
            parseSnapshot(
                text: rawText,
                selection: snapshot.range
            )
        )
        saveCurrentDraft()
        updateCurrentLocationNeed()
        schedulePlaceSearchIfNeeded()
        scheduleRouteSuggestions()
        refreshSuggestions()
        renderEditorText(rawText, selectionSnapshot: snapshot)
    }

    private func parseSnapshot(
        text: String,
        selection: Range<Int>
    ) -> ComposerParseSnapshot {
        GuidedComposerSemanticParser.parse(
            GuidedComposerSemanticParser.Input(
                text: text,
                selection: selection,
                bindings: semanticBindings,
                transitTypes: transitTypes,
                locations: allLocationCandidates(),
                people: people,
                selectedDay: selectedDay
            )
        )
    }

    private func applyParseSnapshot(
        _ snapshot: ComposerParseSnapshot
    ) {
        let snapshot = stabilized(snapshot)
        draft = ComposerDraft(tokens: snapshot.tokens)
        tokenRanges = snapshot.tokenRanges
        activeRange = snapshot.activeRange
        activeSlot = snapshot.activeSlot
        activeQuery = snapshot.activeQuery
        continuationContext = snapshot.continuation
        parseAlternatives = snapshot.alternatives
        isSyntaxValid = snapshot.isSyntaxValid
        if let token = draft.tokens.first(where: {
            guard let range = tokenRanges[$0.id] else { return false }
            return range == activeRange
        }), case .time(let value, let role) = token.value {
            let resolvedValue = role == .end
                ? draft.endTime ?? value
                : value
            activeTimePickerSeed = ComposerTimePickerSeed(
                id: token.id,
                role: role,
                date: resolvedValue.date,
                timeZoneIdentifier: resolvedValue.timeZoneIdentifier
            )
        } else {
            activeTimePickerSeed = nil
        }
    }

    private func stabilized(
        _ snapshot: ComposerParseSnapshot
    ) -> ComposerParseSnapshot {
        let previousTokens = draft.tokens
        let previousRanges = tokenRanges
        let spans = snapshot.spans.map { span in
            guard let previous = previousTokens.first(where: {
                previousRanges[$0.id] == span.range
                    && $0.value == span.token.value
                    && $0.displayText == span.token.displayText
            }) else {
                return span
            }
            return ComposerSemanticSpan(
                token: ComposerToken(
                    id: previous.id,
                    displayText: span.token.displayText,
                    value: span.token.value
                ),
                range: span.range,
                resolution: span.resolution
            )
        }
        return ComposerParseSnapshot(
            spans: spans,
            clauseRanges: snapshot.clauseRanges,
            activeRange: snapshot.activeRange,
            activeSlot: snapshot.activeSlot,
            activeQuery: snapshot.activeQuery,
            continuation: snapshot.continuation,
            alternatives: snapshot.alternatives,
            isSyntaxValid: snapshot.isSyntaxValid
        )
    }

    private func captureSelection() -> ComposerSelectionSnapshot? {
        switch selection.indices(in: editorText) {
        case .insertionPoint(let index):
            let offset = editorText.characters.distance(
                from: editorText.startIndex,
                to: index
            )
            return ComposerSelectionSnapshot(range: offset..<offset)
        case .ranges(let ranges):
            guard let first = ranges.ranges.first else { return nil }
            let lower = editorText.characters.distance(
                from: editorText.startIndex,
                to: first.lowerBound
            )
            let upper = editorText.characters.distance(
                from: editorText.startIndex,
                to: first.upperBound
            )
            return ComposerSelectionSnapshot(range: lower..<upper)
        }
    }

    private func tokenRange(containing offset: Int) -> Range<Int>? {
        let ranges = draft.tokens.compactMap { token in
            tokenRanges[token.id]
        }
        return ranges.first { range in
            range.contains(offset)
        } ?? ranges.last { range in
            range.upperBound == offset
        } ?? ranges.first { range in
            range.lowerBound == offset
        }
    }

    private func restoreSelection(
        _ snapshot: ComposerSelectionSnapshot?,
        in text: AttributedString
    ) {
        guard let snapshot else { return }
        let safeRange = clamped(snapshot.range, to: text.characters.count)
        guard let lower = text.characters.index(
            text.startIndex,
            offsetBy: safeRange.lowerBound,
            limitedBy: text.endIndex
        ) else {
            return
        }
        if safeRange.isEmpty {
            selection = AttributedTextSelection(insertionPoint: lower)
            return
        }
        guard let upper = text.characters.index(
            text.startIndex,
            offsetBy: safeRange.upperBound,
            limitedBy: text.endIndex
        ) else {
            return
        }
        selection = AttributedTextSelection(range: lower..<upper)
    }

    private func allLocationCandidates() -> [ComposerLocationCandidate] {
        var values = places + mapCandidates
            + timelineContext.endpointCandidates
        for token in semanticTokenMemory + draft.tokens {
            if case .location(let candidate, _) = token.value,
               candidate.source != .savedPlace {
                values.append(candidate)
            }
        }
        return GuidedComposerLocationRanking.deduplicated(values)
    }

    private func tokenBeforeActiveRange() -> ComposerToken? {
        token(before: activeRange.lowerBound)
    }

    private func token(before offset: Int) -> ComposerToken? {
        draft.tokens.last { token in
            guard let range = tokenRanges[token.id] else { return false }
            return range.upperBound <= offset
        }
    }

    private func clamped(
        _ range: Range<Int>,
        to length: Int
    ) -> Range<Int> {
        let lower = min(max(0, range.lowerBound), length)
        let upper = min(max(lower, range.upperBound), length)
        return lower..<upper
    }

    private func render() {
        let selectionSnapshot = captureSelection()
        renderEditorText(
            rawEditorString,
            selectionSnapshot: selectionSnapshot
        )
    }

    private func renderEditorText(
        _ rawText: String,
        selectionSnapshot: ComposerSelectionSnapshot?
    ) {
        isRendering = true
        defer { isRendering = false }

        let result = GuidedComposerTextRenderer.render(
            rawText,
            tokens: draft.tokens,
            ranges: tokenRanges
        )
        editorText = result
        lastRenderedSelectionRange = selectionSnapshot.map {
            clamped($0.range, to: result.characters.count)
        }
        restoreSelection(selectionSnapshot, in: result)
    }

    private func scheduleRouteSuggestions() {
        let signature = routeWorkSignature()
        guard signature != activeRouteSignature else { return }
        activeRouteSignature = signature
        routeSuggestionTask?.cancel()
        routeSuggestionGeneration = UUID()
        let generation = routeSuggestionGeneration
        smartRouteSuggestions = []
        mapKitDurationSuggestion = nil
        mapKitRouteDuration = nil
        isCalculatingRoutes = false

        guard case .transit = draft.entryKind,
              let signature else {
            return
        }
        let input = GuidedComposerRouteSuggestionInput(
            routingMode: signature.routingMode,
            context: timelineContext,
            homeCandidates: places.filter(
                GuidedComposerLocationRanking.isHome
            ),
            isToday: selectedDay == .today(),
            currentLocation: currentLocation,
            draft: draft,
            anchorToEnd: draft.location(.origin) == nil
                && draft.location(.destination) != nil
        )
        isCalculatingRoutes = input.shouldCalculate
        let durationCache = routeDurationCache
        routeSuggestionTask = Task { [weak self] in
            await GuidedComposerRouteSuggestionBuilder.build(
                input: input,
                durationCache: durationCache
            ) { [weak self] state in
                guard let self,
                      !Task.isCancelled,
                      routeSuggestionGeneration == generation else {
                    return
                }
                smartRouteSuggestions = state.suggestions
                mapKitDurationSuggestion = state.durationSuggestion
                mapKitRouteDuration = state.routeDuration
                isCalculatingRoutes = state.isCalculating
                refreshSuggestions()
            }
        }
    }

    private func schedulePlaceSearchIfNeeded() {
        placeSearchTask?.cancel()
        placeSearchGeneration = UUID()
        let generation = placeSearchGeneration
        mapCandidates = []
        isSearchingPlaces = false
        guard case .location = activeSlot else { return }
        let query = activeQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard query.count >= 2, let center = searchCenter else {
            return
        }

        isSearchingPlaces = true
        placeSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled,
                  placeSearchGeneration == generation else {
                return
            }
            let results = try? await TransitMapKitService.search(
                query: query,
                near: center,
                limit: 6
            )
            guard !Task.isCancelled,
                  placeSearchGeneration == generation else {
                return
            }
            mapCandidates = (results ?? []).enumerated().map {
                index,
                result in
                ComposerLocationCandidate(
                    id: "map-\(result.latitude)-\(result.longitude)-\(index)",
                    displayName: result.name,
                    location: result.location,
                    systemImage: result.location.systemImage ?? .mappin,
                    source: .mapKit,
                    searchTerms: [result.address].compactMap { $0 }
                )
            }
            isSearchingPlaces = false
            if let selectionSnapshot = captureSelection() {
                applyParseSnapshot(
                    parseSnapshot(
                        text: rawEditorString,
                        selection: selectionSnapshot.range
                    )
                )
            }
            refreshSuggestions()
            render()
        }
    }

    private var searchCenter: CLLocationCoordinate2D? {
        draft.location(.origin)?.location.coordinate
            ?? draft.location(.destination)?.location.coordinate
            ?? draft.location(.visit)?.location.coordinate
            ?? currentLocation?.coordinate
            ?? places.first?.location.coordinate
            ?? timelineContext.endpointCandidates.first?.location.coordinate
    }

    private func activeTimeZone(for role: ComposerTimeRole) -> TimeZone {
        let identifier: String? = switch draft.entryKind {
        case .placeVisit:
            draft.location(.visit)?.location.timeZoneIdentifier
        case .transit:
            role == .start
                ? draft.location(.origin)?.location.timeZoneIdentifier
                : draft.location(.destination)?.location.timeZoneIdentifier
        case nil:
            nil
        }
        return TimeZone(identifier: identifier ?? "") ?? .current
    }

    private func defaultPickerTime(
        zone: TimeZone,
        now: Date = .now
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let clock = calendar.dateComponents(
            [.hour, .minute],
            from: now
        )
        return calendar.date(
            from: DateComponents(
                timeZone: zone,
                year: selectedDay.year,
                month: selectedDay.month,
                day: selectedDay.day,
                hour: clock.hour,
                minute: clock.minute
            )
        ) ?? selectedDay.displayDate(in: zone)
    }

    private func saveCurrentDraft() {
        draftsByDay[selectedDay] = draft
        rawDraftsByDay[selectedDay] = rawEditorString
        bindingsByDay[selectedDay] = semanticBindings
    }

    private var currentLocation: Location? {
        currentLocationCoordinator.freshLocation
    }

    private func routeWorkSignature()
        -> GuidedComposerRouteWorkSignature? {
        guard let entryKind = draft.entryKind,
              case .transit(let canonicalName) = entryKind else {
            return nil
        }
        let routingMode = transitTypes.first {
            $0.canonicalName == canonicalName
        }?.routingMode ?? .automobile
        return GuidedComposerRouteWorkSignature(
            entryKind: entryKind,
            routingMode: routingMode,
            origin: draft.location(.origin).map {
                GuidedComposerRouteWorkSignature.Endpoint($0)
            },
            destination: draft.location(.destination).map {
                GuidedComposerRouteWorkSignature.Endpoint($0)
            },
            selectedDay: selectedDay,
            timelineRevision: contextRevision.timelineRevision,
            repositoryGeneration: contextGeneration,
            currentLocation: currentLocation.map {
                GuidedComposerRouteWorkSignature.LocationBucket($0)
            },
            currentLocationCapturedAt: currentLocation == nil
                ? nil
                : currentLocationCoordinator.snapshot?.capturedAt
        )
    }

    private var needsCurrentLocation: Bool {
        guard selectedDay == .today() else { return false }
        if case .location = activeSlot {
            return true
        }
        guard case .transit = draft.entryKind else { return false }
        return draft.location(.origin) != nil
            || draft.location(.destination) != nil
            || !timelineContext.intervals.isEmpty
    }

    private func updateCurrentLocationNeed() {
        currentLocationCoordinator.update(
            isNeeded: needsCurrentLocation,
            isToday: selectedDay == .today(),
            onChange: currentLocationDidChange
        )
        locationStatusMessage = needsCurrentLocation
            ? currentLocationCoordinator.status.message
            : nil
    }

    private func currentLocationDidChange() {
        locationStatusMessage = needsCurrentLocation
            ? currentLocationCoordinator.status.message
            : nil
        schedulePlaceSearchIfNeeded()
        scheduleRouteSuggestions()
        refreshSuggestions()
    }

    private func connectorSubtitle(_ slot: ComposerSlot) -> String? {
        ComposerSlotPresentation.subtitle(for: slot)
    }

    private func connectorSystemImage(_ slot: ComposerSlot) -> String {
        ComposerSlotPresentation.systemImage(for: slot)
    }

    private func accessibilityRole(_ role: ComposerValueRole) -> String {
        switch role {
        case .leading:
            String(localized: "entry type or description")
        case .connector:
            String(localized: "connector")
        case .location(.visit):
            String(localized: "visit place")
        case .location(.origin):
            String(localized: "origin")
        case .location(.destination):
            String(localized: "destination")
        case .time(.start):
            String(localized: "start time")
        case .time(.end):
            String(localized: "end time")
        case .duration:
            String(localized: "duration")
        case .person:
            String(localized: "person")
        }
    }

    private func exactDisplayText(
        query: String,
        fallback: String,
        terms: [String]
    ) -> String {
        terms.contains {
            GuidedComposerNormalization.text($0)
                == GuidedComposerNormalization.text(query)
        } ? query : fallback
    }

    private func relatedTransitBonus(_ canonicalName: String) -> Int {
        guard let selected = draft.entryKind else { return 0 }
        guard case .transit(let currentName) = selected else { return 0 }
        return GuidedComposerTransitFamily.areRelated(
            currentName,
            canonicalName
        ) ? 600 : 0
    }

}

#if DEBUG
extension GuidedEntryComposerModel {
    static func preview(
        suggestions: [ComposerSuggestion],
        activeSlot: ComposerSlot = .connector,
        isSearchingPlaces: Bool = false,
        isCalculatingRoutes: Bool = false,
        locationStatusMessage: String? = nil
    ) -> GuidedEntryComposerModel {
        let model = GuidedEntryComposerModel()
        model.suggestions = suggestions
        model.activeSuggestionID = suggestions.first?.id
        model.activeSlot = activeSlot
        model.isSearchingPlaces = isSearchingPlaces
        model.isCalculatingRoutes = isCalculatingRoutes
        model.locationStatusMessage = locationStatusMessage
        return model
    }
}
#endif

private struct ComposerSelectionSnapshot {
    let range: Range<Int>

    var upperBound: Int {
        range.upperBound
    }
}
