//
//  TransitResolutionService.swift
//  Journal
//

import CoreLocation
import Foundation

struct ResolvedTransitDraft {
    var transitType: String
    var originPlace: Place?
    var originRawText: String?
    var destinationPlace: Place?
    var destinationRawText: String?
    var startTime: Date?
    var endTime: Date?
    var timeConfidence: TimeConfidence
    var people: [Person]
    var durationSource: DurationSource
    var originCandidates: [PlaceCandidate]
    var destinationCandidates: [PlaceCandidate]
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
            origin: origin.place,
            destination: destination.place,
            currentLocation: currentLocation,
            now: now,
            selectedDayEntries: selectedDayEntries
        )

        var draft = ResolvedTransitDraft(
            transitType: typeResolution.name,
            originPlace: origin.place,
            originRawText: generated.origin.rawText,
            destinationPlace: destination.place,
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
        resolution: PlaceResolution,
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
        } else if resolution.place == nil {
            let fallback = resolution.candidates.isEmpty
                ? String(localized: "No saved place or plausible search candidate was resolved.")
                : String(localized: "Choose or save one of the suggested places.")
            draft.requireReview(field, reason: fallback)
        }
    }

    private static func resolvePlace(
        _ generated: GeneratedPlaceResolution,
        endpoint: GeneratedPlaceRole,
        references: EntryPromptReferences,
        searches: [TransitToolSearch]
    ) -> PlaceResolution {
        if let key = generated.savedPlaceKey {
            guard let place = references.placesByKey[key] else {
                return PlaceResolution(
                    place: nil,
                    candidates: candidates(
                        keys: generated.candidateKeys,
                        endpoint: endpoint,
                        searches: searches
                    ),
                    validationError: String(localized: "The model returned an unknown saved-place key.")
                )
            }
            return PlaceResolution(place: place, candidates: [], validationError: nil)
        }

        return PlaceResolution(
            place: nil,
            candidates: candidates(
                keys: generated.candidateKeys,
                endpoint: endpoint,
                searches: searches
            ),
            validationError: nil
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
        origin: Place?,
        destination: Place?,
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
        origin: Place?,
        destination: Place?,
        selectedDayEntries: [LogEntry]
    ) -> String? {
        if let rawText, !normalize(rawText).isEmpty {
            return String(localized: "A history-inferred time must not claim explicit time wording.")
        }
        guard let start, let end else {
            return String(localized: "The model did not complete both history-inferred trip timestamps.")
        }
        guard let origin, let destination else {
            return String(localized: "Both saved places are required to validate a history-inferred time.")
        }

        let hasStartAnchor = selectedDayEntries.contains { entry in
            isUsableHistoryEndAnchor(entry)
                && approximatelyEqual(entry.endTime, start)
                && historyEndPlaceID(entry) == origin.id
        }
        let hasEndAnchor = selectedDayEntries.contains { entry in
            isUsableHistoryStartAnchor(entry)
                && approximatelyEqual(entry.startTime, end)
                && historyStartPlaceID(entry) == destination.id
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
                    && details.originPlace != nil
                : !reviewedFields.contains(.place)
                    && details.place != nil
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
                    && details.destinationPlace != nil
                : !reviewedFields.contains(.place)
                    && details.place != nil
        }
    }

    private static func historyStartPlaceID(_ entry: LogEntry) -> UUID? {
        switch entry.kind {
        case .transit:
            entry.transitDetails?.originPlace?.id
        case .placeVisit:
            entry.placeVisitDetails?.place?.id
        case .workout:
            if entry.workoutDetails?.movementKind == .moving {
                entry.workoutDetails?.originPlace?.id
            } else {
                entry.workoutDetails?.place?.id
            }
        }
    }

    private static func historyEndPlaceID(_ entry: LogEntry) -> UUID? {
        switch entry.kind {
        case .transit:
            entry.transitDetails?.destinationPlace?.id
        case .placeVisit:
            entry.placeVisitDetails?.place?.id
        case .workout:
            if entry.workoutDetails?.movementKind == .moving {
                entry.workoutDetails?.destinationPlace?.id
            } else {
                entry.workoutDetails?.place?.id
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
        origin: Place?,
        destination: Place?,
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
            return String(localized: "Both saved places are required to validate inferred time.")
        }

        let nearOrigin = isNear(currentLocation, place: origin)
        let nearDestination = isNear(currentLocation, place: destination)
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
        searches: [TransitToolSearch]
    ) -> [PlaceCandidate] {
        let available = Dictionary(
            uniqueKeysWithValues: searches
                .filter { $0.role == endpoint }
                .flatMap(\.candidates)
                .map { ($0.candidateKey, $0.result) }
        )
        var seen: Set<String> = []

        return keys.compactMap { key in
            guard seen.insert(key).inserted,
                  let result = available[key] else {
                return nil
            }
            return PlaceCandidate(
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

    private static func parsedDate(_ value: String?) -> Date? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return try? Date(value, strategy: .iso8601)
    }

    private static func isNear(_ location: Location, place: Place) -> Bool {
        let distance = CLLocation(
            latitude: location.latitude,
            longitude: location.longitude
        ).distance(
            from: CLLocation(
                latitude: place.location.latitude,
                longitude: place.location.longitude
            )
        )
        return distance <= max(200, place.accuracyRadiusMeters)
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

private struct PlaceResolution {
    let place: Place?
    let candidates: [PlaceCandidate]
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
