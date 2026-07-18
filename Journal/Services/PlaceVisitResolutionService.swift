//
//  PlaceVisitResolutionService.swift
//  Journal
//

import Foundation

struct ResolvedPlaceVisitDraft {
    var place: Place?
    var placeRawText: String?
    var startTime: Date?
    var endTime: Date?
    var timeConfidence: TimeConfidence
    var people: [Person]
    var candidates: [PlaceCandidate]
    var unresolvedPeople: [String]
    var fieldReviews: [PlaceVisitFieldReview]
    var entryKindReviewReason: String?

    var needsReview: Bool {
        entryKindReviewReason != nil || !fieldReviews.isEmpty
    }

    mutating func requireReview(
        _ field: PlaceVisitReviewField,
        reason: String
    ) {
        guard !fieldReviews.contains(where: { $0.field == field }) else {
            return
        }
        fieldReviews.append(
            PlaceVisitFieldReview(field: field, reason: reason)
        )
    }
}

enum PlaceVisitResolutionService {
    static func resolve(
        generated: GeneratedPlaceVisitLog,
        entryKindReview: GeneratedFieldReview,
        references: EntryPromptReferences,
        toolSearches: [TransitToolSearch],
        rawInput: String,
        people: [Person]
    ) -> ResolvedPlaceVisitDraft {
        let placeResolution = resolvePlace(
            generated.place,
            references: references,
            searches: toolSearches
        )
        let peopleResolution = resolvePeople(
            generated.people,
            references: references,
            people: people
        )
        let timeResolution = resolveTime(
            generated.time,
            rawInput: rawInput
        )

        var draft = ResolvedPlaceVisitDraft(
            place: placeResolution.place,
            placeRawText: generated.place.rawText,
            startTime: timeResolution.start,
            endTime: timeResolution.end,
            timeConfidence: timeResolution.confidence,
            people: peopleResolution.people,
            candidates: placeResolution.candidates,
            unresolvedPeople: peopleResolution.unresolved,
            fieldReviews: [],
            entryKindReviewReason: entryKindReview.needsReview
                ? reviewReason(
                    entryKindReview,
                    fallback: String(localized: "The entry type is ambiguous.")
                )
                : nil
        )

        if generated.place.review.needsReview {
            draft.requireReview(
                .place,
                reason: reviewReason(
                    generated.place.review,
                    fallback: String(localized: "The visited place is ambiguous.")
                )
            )
        }
        if let error = placeResolution.validationError {
            draft.requireReview(.place, reason: error)
        } else if placeResolution.place == nil {
            draft.requireReview(
                .place,
                reason: placeResolution.candidates.isEmpty
                    ? String(localized: "No saved place or plausible search candidate was resolved.")
                    : String(localized: "Choose or save one of the suggested places.")
            )
        }

        if generated.time.review.needsReview {
            draft.requireReview(
                .time,
                reason: reviewReason(
                    generated.time.review,
                    fallback: String(localized: "The visit time is incomplete or ambiguous.")
                )
            )
        }
        if let error = timeResolution.validationError {
            draft.requireReview(.time, reason: error)
        }

        if let reason = peopleResolution.reviewReason {
            draft.requireReview(.people, reason: reason)
        }

        return draft
    }

    private static func resolvePlace(
        _ generated: GeneratedPlaceResolution,
        references: EntryPromptReferences,
        searches: [TransitToolSearch]
    ) -> PlaceVisitPlaceResolution {
        if let key = generated.savedPlaceKey {
            guard let place = references.placesByKey[key] else {
                return PlaceVisitPlaceResolution(
                    place: nil,
                    candidates: candidates(
                        keys: generated.candidateKeys,
                        searches: searches
                    ),
                    validationError: String(localized: "The model returned an unknown saved-place key.")
                )
            }
            return PlaceVisitPlaceResolution(
                place: place,
                candidates: [],
                validationError: generated.candidateKeys.isEmpty
                    ? nil
                    : String(localized: "A saved place must not also contain search candidates.")
            )
        }

        let resolvedCandidates = candidates(
            keys: generated.candidateKeys,
            searches: searches
        )
        let unknownCandidate = resolvedCandidates.count
            != Set(generated.candidateKeys).count
        return PlaceVisitPlaceResolution(
            place: nil,
            candidates: resolvedCandidates,
            validationError: unknownCandidate
                ? String(localized: "The model returned an unknown place candidate key.")
                : nil
        )
    }

    private static func candidates(
        keys: [String],
        searches: [TransitToolSearch]
    ) -> [PlaceCandidate] {
        let available = Dictionary(
            searches
                .filter { $0.role == .visit }
                .flatMap(\.candidates)
                .map { ($0.candidateKey, $0.result) },
            uniquingKeysWith: { first, _ in first }
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

    private static func resolvePeople(
        _ generated: [GeneratedPersonResolution],
        references: EntryPromptReferences,
        people: [Person]
    ) -> PlaceVisitPeopleResolution {
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
                        String(localized: "Several people match a name in the visit text.")
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
        return PlaceVisitPeopleResolution(
            people: resolved,
            unresolved: unresolved,
            reviewReason: reasons.first
        )
    }

    private static func resolveTime(
        _ generated: GeneratedPlaceVisitTimeResolution,
        rawInput: String
    ) -> PlaceVisitTimeResolution {
        let start = parsedDate(generated.startTimeISO8601)
        let end = parsedDate(generated.endTimeISO8601)
        let suppliedInvalid = (generated.startTimeISO8601 != nil && start == nil)
            || (generated.endTimeISO8601 != nil && end == nil)

        if suppliedInvalid {
            return PlaceVisitTimeResolution(
                start: start,
                end: end,
                confidence: start == nil && end == nil ? .unresolved : .explicit,
                validationError: String(localized: "The model returned an invalid visit timestamp.")
            )
        }
        if let start, let end, end <= start {
            return PlaceVisitTimeResolution(
                start: start,
                end: end,
                confidence: .explicit,
                validationError: String(localized: "The visit end time must be after its start time.")
            )
        }
        if start != nil || end != nil {
            guard let rawText = generated.rawText,
                  !normalize(rawText).isEmpty,
                  normalize(rawInput).contains(normalize(rawText)) else {
                return PlaceVisitTimeResolution(
                    start: start,
                    end: end,
                    confidence: .explicit,
                    validationError: String(localized: "The visit time is not supported by the original text.")
                )
            }
        }
        if start == nil || end == nil {
            return PlaceVisitTimeResolution(
                start: start,
                end: end,
                confidence: start == nil && end == nil ? .unresolved : .explicit,
                validationError: generated.review.needsReview
                    ? nil
                    : String(localized: "An incomplete visit interval must be marked for review.")
            )
        }
        return PlaceVisitTimeResolution(
            start: start,
            end: end,
            confidence: .explicit,
            validationError: nil
        )
    }

    private static func parsedDate(_ value: String?) -> Date? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return try? Date(value, strategy: .iso8601)
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

    private static func normalize(_ value: String) -> String {
        TransitResolutionService.normalize(value)
    }
}

private struct PlaceVisitPlaceResolution {
    let place: Place?
    let candidates: [PlaceCandidate]
    let validationError: String?
}

private struct PlaceVisitPeopleResolution {
    let people: [Person]
    let unresolved: [String]
    let reviewReason: String?
}

private struct PlaceVisitTimeResolution {
    let start: Date?
    let end: Date?
    let confidence: TimeConfidence
    let validationError: String?
}
