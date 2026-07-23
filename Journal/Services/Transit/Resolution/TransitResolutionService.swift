import CoreLocation
import Foundation

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

    static func applyPlaceReview(
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

    static func resolvePlace(
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

    static func resolvedTransitType(
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

    static func resolvePeople(
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

}
