import CoreLocation
import Foundation

extension TransitResolutionService {
    static func resolvedTime(
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

    static func historyInferenceValidationError(
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

    static func isUsableHistoryStartAnchor(_ entry: LogEntry) -> Bool {
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
        case .wakeUp:
            return false
        }
    }

    static func isUsableHistoryEndAnchor(_ entry: LogEntry) -> Bool {
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
        case .wakeUp:
            return false
        }
    }

    static func historyStartLocation(_ entry: LogEntry) -> Location? {
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
        case .wakeUp:
            nil
        }
    }

    static func historyEndLocation(_ entry: LogEntry) -> Location? {
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
        case .wakeUp:
            nil
        }
    }

    static func approximatelyEqual(_ lhs: Date?, _ rhs: Date) -> Bool {
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

    static func confidence(
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

}
