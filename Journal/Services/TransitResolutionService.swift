//
//  TransitResolutionService.swift
//  Journal
//

import CoreLocation
import Foundation

struct ResolvedTransitDraft {
    var transitType: String
    var originPlace: Place?
    var originLocation: Location?
    var originRawText: String?
    var destinationPlace: Place?
    var destinationLocation: Location?
    var destinationRawText: String?
    var startTime: Date?
    var endTime: Date?
    var timeConfidence: TimeConfidence
    var people: [Person]
    var durationSource: DurationSource
    var originCandidates: [LocationCandidate]
    var destinationCandidates: [LocationCandidate]
    var unresolvedPeople: [String]
    var fieldReviews: [TransitFieldReview]
    var entryKindReviewReason: String? = nil

    var needsReview: Bool {
        entryKindReviewReason != nil || !fieldReviews.isEmpty
    }

    mutating func requireReview(
        _ field: TransitReviewField,
        reason: String
    ) {
        guard !fieldReviews.contains(where: { $0.field == field }) else {
            return
        }
        fieldReviews.append(TransitFieldReview(field: field, reason: reason))
    }
}

enum TransitResolutionService {
    static func resolve(
        generated: GeneratedTransitLog,
        references: EntryPromptReferences,
        toolSearches: [TransitToolSearch],
        rawInput: String,
        people: [Person],
        transitTypes: [TransitType],
        currentLocation: Location,
        now: Date,
        selectedDayEntries: [LogEntry]
    ) -> ResolvedTransitDraft {
        let typeResolution = resolvedTransitType(
            generated.transitType.canonicalName,
            definitions: transitTypes
        )
        let origin = resolvePlace(
            generated.origin,
            endpoint: .origin,
            references: references,
            searches: toolSearches
        )
        let destination = resolvePlace(
            generated.destination,
            endpoint: .destination,
            references: references,
            searches: toolSearches
        )
        let resolvedPeople = resolvePeople(
            generated.people,
            references: references,
            people: people
        )
        let time = resolvedTime(
            generated.time,
            rawInput: rawInput,
            origin: origin.location,
            destination: destination.location,
            currentLocation: currentLocation,
            now: now,
            selectedDayEntries: selectedDayEntries
        )

        var draft = ResolvedTransitDraft(
            transitType: typeResolution.name,
            originPlace: origin.place,
            originLocation: origin.location,
            originRawText: generated.origin.rawText,
            destinationPlace: destination.place,
            destinationLocation: destination.location,
            destinationRawText: generated.destination.rawText,
            startTime: time.start,
            endTime: time.end,
            timeConfidence: time.confidence,
            people: resolvedPeople.people,
            durationSource: time.durationSource,
            originCandidates: origin.candidates,
            destinationCandidates: destination.candidates,
            unresolvedPeople: resolvedPeople.unresolved,
            fieldReviews: []
        )

        if generated.transitType.review.needsReview {
            draft.requireReview(
                .transitType,
                reason: reviewReason(
                    generated.transitType.review,
                    fallback: String(localized: "The transit type is ambiguous.")
                )
            )
        } else if !typeResolution.isKnown {
            draft.requireReview(
                .transitType,
                reason: String(localized: "The transit type is not in your saved transit types.")
            )
        }

        applyPlaceReview(
            generated.origin.review,
            resolution: origin,
            field: .origin,
            draft: &draft
        )
        applyPlaceReview(
            generated.destination.review,
            resolution: destination,
            field: .destination,
            draft: &draft
        )

        if generated.time.review.needsReview {
            draft.requireReview(
                .time,
                reason: reviewReason(
                    generated.time.review,
                    fallback: String(localized: "The time wording is ambiguous.")
                )
            )
        }
        if let timeError = time.error {
            draft.requireReview(.time, reason: timeError)
        }

        if let peopleReason = resolvedPeople.reviewReason {
            draft.requireReview(.people, reason: peopleReason)
        }

        return draft
    }

    private static func applyPlaceReview(
        _ modelReview: GeneratedFieldReview,
        resolution: LocationResolution,
        field: TransitReviewField,
        draft: inout ResolvedTransitDraft
    ) {
        if modelReview.needsReview {
            draft.requireReview(
                field,
                reason: reviewReason(
                    modelReview,
                    fallback: String(localized: "This place is ambiguous.")
                )
            )
        }

        if let validationError = resolution.validationError {
            draft.requireReview(field, reason: validationError)
        } else if resolution.location == nil {
            let fallback = resolution.candidates.isEmpty
                ? String(localized: "No usable location was resolved.")
                : String(localized: "Choose one of the suggested locations.")
            draft.requireReview(field, reason: fallback)
        }
    }

    private static func resolvePlace(
        _ generated: GeneratedLocationResolution,
        endpoint: GeneratedPlaceRole,
        references: EntryPromptReferences,
        searches: [TransitToolSearch]
    ) -> LocationResolution {
        let alternatives = candidates(
            keys: generated.alternativeLocationKeys,
            endpoint: endpoint,
            references: references,
            searches: searches
        )
        guard let key = generated.selectedLocationKey else {
            return LocationResolution(
                place: nil,
                location: nil,
                candidates: alternatives,
                validationError: generated.alternativeLocationKeys.isEmpty
                    ? nil
                    : String(localized: "Location alternatives require a best selected location.")
            )
        }

        if let reference = references.locationsByKey[key] {
            return LocationResolution(
                place: reference.place,
                location: reference.location,
                candidates: alternatives,
                validationError: nil
            )
        }
        if let result = searchResult(
            key: key,
            endpoint: endpoint,
            searches: searches
        ) {
            return LocationResolution(
                place: nil,
                location: result.location,
                candidates: alternatives,
                validationError: nil
            )
        }
        return LocationResolution(
            place: nil,
            location: nil,
            candidates: alternatives,
            validationError: String(localized: "The model returned an unknown location key.")
        )
    }

    private static func resolvedTransitType(
        _ generatedType: String,
        definitions: [TransitType]
    ) -> (name: String, isKnown: Bool) {
        let needle = normalize(generatedType)
        if let exactMatch = definitions.first(where: {
            normalize($0.canonicalName) == needle
        }) {
            return (exactMatch.canonicalName, true)
        }

        if let aliasMatch = definitions.first(where: { definition in
            definition.aliases.contains {
                normalize($0) == needle
            }
        }) {
            return (aliasMatch.canonicalName, true)
        }

        return (
            generatedType.trimmingCharacters(in: .whitespacesAndNewlines),
            false
        )
    }

    private static func resolvePeople(
        _ generated: [GeneratedPersonResolution],
        references: EntryPromptReferences,
        people: [Person]
    ) -> PeopleResolution {
        var resolved: [Person] = []
        var unresolved: [String] = []
        var reasons: [String] = []

        for item in generated {
            if item.review.needsReview {
                unresolved.append(item.rawText)
                reasons.append(
                    reviewReason(
                        item.review,
                        fallback: String(localized: "A person could not be resolved confidently.")
                    )
                )
                continue
            }

            let person: Person?
            if let key = item.personKey {
                person = references.peopleByKey[key]
                if person == nil {
                    reasons.append(
                        String(localized: "The model returned an unknown person key.")
                    )
                }
            } else {
                let matches = people.filter { person in
                    ([person.name] + person.aliases).contains {
                        normalize($0) == normalize(item.rawText)
                    }
                }
                person = matches.count == 1 ? matches[0] : nil
                if matches.count > 1 {
                    reasons.append(
                        String(localized: "Several people match a name in the transit text.")
                    )
                }
            }

            if let person {
                if !resolved.contains(where: { $0.id == person.id }) {
                    resolved.append(person)
                }
            } else {
                unresolved.append(item.rawText)
            }

        }

        if !unresolved.isEmpty, reasons.isEmpty {
            reasons.append(
                String(localized: "One or more people could not be matched to saved people.")
            )
        }

        return PeopleResolution(
            people: resolved,
            unresolved: unresolved,
            reviewReason: reasons.first
        )
    }

    private static func resolvedTime(
        _ generated: GeneratedTimeResolution,
        rawInput: String,
        origin: Location?,
        destination: Location?,
        currentLocation: Location,
        now: Date,
        selectedDayEntries: [LogEntry]
    ) -> TimeResolution {
        let start = parsedDate(generated.startTimeISO8601)
        let end = parsedDate(generated.endTimeISO8601)
        let suppliedUnparseableDate = (
            generated.startTimeISO8601 != nil && start == nil
        ) || (
            generated.endTimeISO8601 != nil && end == nil
        )

        if suppliedUnparseableDate {
            return TimeResolution(
                start: start,
                end: end,
                confidence: confidence(for: generated.resolutionKind),
                durationSource: durationSource(for: generated.durationSource),
                error: String(localized: "The model returned an invalid timestamp.")
            )
        }

        if let start, let end, end <= start {
            return TimeResolution(
                start: start,
                end: end,
                confidence: confidence(for: generated.resolutionKind),
                durationSource: durationSource(for: generated.durationSource),
                error: String(localized: "The end time must be after the start time.")
            )
        }

        let error: String?
        switch generated.resolutionKind {
        case .explicit:
            guard let rawText = generated.rawText,
                  !normalize(rawText).isEmpty,
                  normalize(rawInput).contains(normalize(rawText)) else {
                return TimeResolution(
                    start: start,
                    end: end,
                    confidence: .explicit,
                    durationSource: durationSource(for: generated.durationSource),
                    error: String(localized: "The explicit time is not supported by the original text.")
                )
            }
            error = start == nil || end == nil
                ? String(localized: "The model did not complete both trip timestamps.")
                : nil

        case .inferredFromHistory:
            error = historyInferenceValidationError(
                rawText: generated.rawText,
                start: start,
                end: end,
                durationSource: generated.durationSource,
                origin: origin,
                destination: destination,
                selectedDayEntries: selectedDayEntries
            )

        case .inferredNearOrigin:
            error = inferenceValidationError(
                expectedAnchor: .origin,
                rawText: generated.rawText,
                start: start,
                end: end,
                durationSource: generated.durationSource,
                origin: origin,
                destination: destination,
                currentLocation: currentLocation,
                now: now
            )

        case .inferredNearDestination:
            error = inferenceValidationError(
                expectedAnchor: .destination,
                rawText: generated.rawText,
                start: start,
                end: end,
                durationSource: generated.durationSource,
                origin: origin,
                destination: destination,
                currentLocation: currentLocation,
                now: now
            )

        case .unresolved:
            if start != nil || end != nil {
                error = String(localized: "An unresolved time must not contain timestamps.")
            } else if !generated.review.needsReview {
                error = String(localized: "The model left the trip time unresolved without requesting review.")
            } else {
                error = nil
            }
        }

        return TimeResolution(
            start: start,
            end: end,
            confidence: confidence(for: generated.resolutionKind),
            durationSource: durationSource(for: generated.durationSource),
            error: error
        )
    }

    private enum InferenceAnchor {
        case origin
        case destination
    }

    private static func historyInferenceValidationError(
        rawText: String?,
        start: Date?,
        end: Date?,
        durationSource: GeneratedDurationSource,
        origin: Location?,
        destination: Location?,
        selectedDayEntries: [LogEntry]
    ) -> String? {
        if let rawText, !normalize(rawText).isEmpty {
            return String(localized: "A history-inferred time must not claim explicit time wording.")
        }
        guard let start, let end else {
            return String(localized: "The model did not complete both history-inferred trip timestamps.")
        }
        guard let origin, let destination else {
            return String(localized: "Both locations are required to validate a history-inferred time.")
        }

        let hasStartAnchor = selectedDayEntries.contains { entry in
            isUsableHistoryEndAnchor(entry)
                && approximatelyEqual(entry.endTime, start)
                && sameLocation(historyEndLocation(entry), origin)
        }
        let hasEndAnchor = selectedDayEntries.contains { entry in
            isUsableHistoryStartAnchor(entry)
                && approximatelyEqual(entry.startTime, end)
                && sameLocation(historyStartLocation(entry), destination)
        }
        guard hasStartAnchor || hasEndAnchor else {
            return String(localized: "The inferred trip time does not match a confirmed selected-day history boundary.")
        }
        if durationSource == .none, !(hasStartAnchor && hasEndAnchor) {
            return String(localized: "The history-inferred trip time has no route-duration source.")
        }
        return nil
    }

    private static func isUsableHistoryStartAnchor(_ entry: LogEntry) -> Bool {
        guard entry.entryKindReviewReason == nil else { return false }
        switch entry.kind {
        case .transit:
            let reviewedFields = entry.transitDetails?.fieldReviews.map(\.field) ?? []
            return !reviewedFields.contains(.time)
                && !reviewedFields.contains(.origin)
        case .placeVisit:
            let reviewedFields = entry.placeVisitDetails?.fieldReviews.map(\.field) ?? []
            return !reviewedFields.contains(.time)
                && !reviewedFields.contains(.place)
        case .workout:
            guard let details = entry.workoutDetails else { return false }
            let reviewedFields = Set(details.fieldReviews.map(\.field))
            return details.movementKind == .moving
                ? !reviewedFields.contains(.origin)
                    && (details.originLocation ?? details.originPlace?.location) != nil
                : !reviewedFields.contains(.place)
                    && (details.sourceLocation ?? details.place?.location) != nil
        }
    }

    private static func isUsableHistoryEndAnchor(_ entry: LogEntry) -> Bool {
        guard entry.entryKindReviewReason == nil else { return false }
        switch entry.kind {
        case .transit:
            let reviewedFields = entry.transitDetails?.fieldReviews.map(\.field) ?? []
            return !reviewedFields.contains(.time)
                && !reviewedFields.contains(.destination)
        case .placeVisit:
            let reviewedFields = entry.placeVisitDetails?.fieldReviews.map(\.field) ?? []
            return !reviewedFields.contains(.time)
                && !reviewedFields.contains(.place)
        case .workout:
            guard let details = entry.workoutDetails else { return false }
            let reviewedFields = Set(details.fieldReviews.map(\.field))
            return details.movementKind == .moving
                ? !reviewedFields.contains(.destination)
                    && (details.destinationLocation ?? details.destinationPlace?.location) != nil
                : !reviewedFields.contains(.place)
                    && (details.sourceLocation ?? details.place?.location) != nil
        }
    }

    private static func historyStartLocation(_ entry: LogEntry) -> Location? {
        switch entry.kind {
        case .transit:
            entry.transitDetails?.originLocation
                ?? entry.transitDetails?.originPlace?.location
        case .placeVisit:
            entry.placeVisitDetails?.location
                ?? entry.placeVisitDetails?.place?.location
        case .workout:
            if entry.workoutDetails?.movementKind == .moving {
                entry.workoutDetails?.originLocation
                    ?? entry.workoutDetails?.originPlace?.location
            } else {
                entry.workoutDetails?.sourceLocation
                    ?? entry.workoutDetails?.place?.location
            }
        }
    }

    private static func historyEndLocation(_ entry: LogEntry) -> Location? {
        switch entry.kind {
        case .transit:
            entry.transitDetails?.destinationLocation
                ?? entry.transitDetails?.destinationPlace?.location
        case .placeVisit:
            entry.placeVisitDetails?.location
                ?? entry.placeVisitDetails?.place?.location
        case .workout:
            if entry.workoutDetails?.movementKind == .moving {
                entry.workoutDetails?.destinationLocation
                    ?? entry.workoutDetails?.destinationPlace?.location
            } else {
                entry.workoutDetails?.sourceLocation
                    ?? entry.workoutDetails?.place?.location
            }
        }
    }

    private static func approximatelyEqual(_ lhs: Date?, _ rhs: Date) -> Bool {
        guard let lhs else { return false }
        return abs(lhs.timeIntervalSince(rhs)) <= 60
    }

    private static func inferenceValidationError(
        expectedAnchor: InferenceAnchor,
        rawText: String?,
        start: Date?,
        end: Date?,
        durationSource: GeneratedDurationSource,
        origin: Location?,
        destination: Location?,
        currentLocation: Location,
        now: Date
    ) -> String? {
        if let rawText, !normalize(rawText).isEmpty {
            return String(localized: "A proximity-inferred time must not claim explicit time wording.")
        }
        guard let start, let end else {
            return String(localized: "The model did not complete both inferred trip timestamps.")
        }
        guard durationSource != .none else {
            return String(localized: "The inferred trip time has no route-duration source.")
        }
        guard let origin, let destination else {
            return String(localized: "Both locations are required to validate inferred time.")
        }

        let nearOrigin = isNear(currentLocation, location: origin)
        let nearDestination = isNear(currentLocation, location: destination)
        switch expectedAnchor {
        case .origin:
            guard nearOrigin, !nearDestination else {
                return String(localized: "Current location does not support an origin-anchored time inference.")
            }
            guard abs(start.timeIntervalSince(now)) <= 5 * 60 else {
                return String(localized: "The inferred departure does not match the supplied current timestamp.")
            }
        case .destination:
            guard nearDestination, !nearOrigin else {
                return String(localized: "Current location does not support a destination-anchored time inference.")
            }
            guard abs(end.timeIntervalSince(now)) <= 5 * 60 else {
                return String(localized: "The inferred arrival does not match the supplied current timestamp.")
            }
        }
        return nil
    }

    private static func confidence(
        for kind: GeneratedTimeResolutionKind
    ) -> TimeConfidence {
        switch kind {
        case .explicit: .explicit
        case .inferredFromHistory: .inferredFromHistory
        case .inferredNearOrigin: .inferredNearOrigin
        case .inferredNearDestination: .inferredNearDestination
        case .unresolved: .unresolved
        }
    }

    private static func durationSource(
        for source: GeneratedDurationSource
    ) -> DurationSource {
        switch source {
        case .none: .unresolved
        case .mapkitWalking: .mapkitWalking
        case .mapkitCarFallback: .mapkitCarFallback
        }
    }

    private static func candidates(
        keys: [String],
        endpoint: GeneratedPlaceRole,
        references: EntryPromptReferences,
        searches: [TransitToolSearch]
    ) -> [LocationCandidate] {
        let searchResults = Dictionary(
            uniqueKeysWithValues: searches
                .filter { $0.role == endpoint }
                .flatMap(\.candidates)
                .map { ($0.candidateKey, $0.result) }
        )
        var seen: Set<String> = []

        return keys.compactMap { key in
            guard seen.insert(key).inserted else { return nil }
            if let reference = references.locationsByKey[key] {
                return LocationCandidate(
                    name: reference.displayName,
                    address: reference.location.formattedAddress,
                    latitude: reference.location.latitude,
                    longitude: reference.location.longitude,
                    timeZoneIdentifier: reference.location.timeZoneIdentifier
                )
            }
            guard let result = searchResults[key] else { return nil }
            return LocationCandidate(
                name: result.name,
                address: result.address,
                latitude: result.latitude,
                longitude: result.longitude,
                timeZoneIdentifier: result.timeZoneIdentifier,
                distanceKilometers: result.distanceKilometers,
                walkingDurationMinutes: result.walkingDurationMinutes,
                automobileDurationMinutes: result.automobileDurationMinutes
            )
        }
    }

    private static func searchResult(
        key: String,
        endpoint: GeneratedPlaceRole,
        searches: [TransitToolSearch]
    ) -> TransitMapSearchResult? {
        searches
            .filter { $0.role == endpoint }
            .flatMap(\.candidates)
            .first { $0.candidateKey == key }?
            .result
    }

    private static func parsedDate(_ value: String?) -> Date? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return try? Date(value, strategy: .iso8601)
    }

    private static func isNear(
        _ currentLocation: Location,
        location: Location
    ) -> Bool {
        let distance = CLLocation(
            latitude: currentLocation.latitude,
            longitude: currentLocation.longitude
        ).distance(
            from: CLLocation(
                latitude: location.latitude,
                longitude: location.longitude
            )
        )
        return distance <= 200
    }

    private static func sameLocation(
        _ lhs: Location?,
        _ rhs: Location
    ) -> Bool {
        guard let lhs else { return false }
        return CLLocation(
            latitude: lhs.latitude,
            longitude: lhs.longitude
        ).distance(
            from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        ) <= 100
    }

    private static func reviewReason(
        _ review: GeneratedFieldReview,
        fallback: String
    ) -> String {
        guard let reason = review.reason?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !reason.isEmpty else {
            return fallback
        }
        return reason
    }

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .lowercased()
    }
}

private struct LocationResolution {
    let place: Place?
    let location: Location?
    let candidates: [LocationCandidate]
    let validationError: String?
}

private struct PeopleResolution {
    let people: [Person]
    let unresolved: [String]
    let reviewReason: String?
}

private struct TimeResolution {
    let start: Date?
    let end: Date?
    let confidence: TimeConfidence
    let durationSource: DurationSource
    let error: String?
}
