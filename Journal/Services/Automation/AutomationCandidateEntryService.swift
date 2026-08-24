import Foundation
import SwiftData

@MainActor
enum AutomationCandidateEntryFactory {
    static func makeEntry(
        for candidate: AutomationCandidate,
        places: [Place],
        needsReview: Bool,
        id: UUID? = nil
    ) -> LogEntry? {
        guard candidate.status == .pending,
              let endTime = candidate.endTime,
              endTime > candidate.startTime else {
            return nil
        }

        let entry: LogEntry?
        switch candidate.kind {
        case .visit:
            entry = makeVisitEntry(
                for: candidate,
                endTime: endTime,
                places: places,
                needsReview: needsReview
            )
        case .transit:
            entry = makeTransitEntry(
                for: candidate,
                endTime: endTime,
                places: places,
                needsReview: needsReview
            )
        }

        guard let entry else { return nil }
        if let id { entry.id = id }
        entry.createdAt = candidate.createdAt
        entry.automationCandidateID = candidate.id
        return entry
    }

    private static func makeVisitEntry(
        for candidate: AutomationCandidate,
        endTime: Date,
        places: [Place],
        needsReview: Bool
    ) -> LogEntry? {
        guard let detectedLocation = candidate.visitLocation else { return nil }
        let place = places.first { $0.id == candidate.visitPlaceID }
        let name = place?.name
            ?? detectedLocation.preferredName
            ?? String(localized: "Detected place")
        let location = (place?.location ?? detectedLocation)
            .withFallbackDisplayName(name)
        let reviews = needsReview
            ? [
                PlaceVisitFieldReview(
                    field: .place,
                    reason: String(localized: "Review the automatically detected place.")
                ),
                PlaceVisitFieldReview(
                    field: .time,
                    reason: String(localized: "Review the automatically detected visit time.")
                ),
            ]
            : []
        let draft = ResolvedPlaceVisitDraft(
            place: place,
            location: location,
            placeRawText: name,
            startTime: candidate.startTime,
            endTime: endTime,
            timeConfidence: .explicit,
            people: [],
            candidates: [],
            unresolvedPeople: [],
            fieldReviews: reviews,
            entryKindReviewReason: nil
        )
        let entry = PlaceVisitEntryStore.makeEntry(draft: draft, rawInput: nil)
        let zone = location.timeZoneIdentifier
            ?? candidate.timeZoneIdentifier
        entry.startTimeZoneIdentifier = zone
        entry.endTimeZoneIdentifier = zone
        return entry
    }

    private static func makeTransitEntry(
        for candidate: AutomationCandidate,
        endTime: Date,
        places: [Place],
        needsReview: Bool
    ) -> LogEntry? {
        guard let detectedOrigin = candidate.originLocation,
              let detectedDestination = candidate.destinationLocation,
              let motionKind = candidate.motionKind else {
            return nil
        }
        let originPlace = places.first { $0.id == candidate.originPlaceID }
        let destinationPlace = places.first {
            $0.id == candidate.destinationPlaceID
        }
        let originName = originPlace?.name
            ?? detectedOrigin.preferredName
            ?? String(localized: "Detected origin")
        let destinationName = destinationPlace?.name
            ?? detectedDestination.preferredName
            ?? String(localized: "Detected destination")
        let originLocation = (originPlace?.location ?? detectedOrigin)
            .withFallbackDisplayName(originName)
        let destinationLocation = (
            destinationPlace?.location ?? detectedDestination
        ).withFallbackDisplayName(destinationName)
        let reviews = needsReview
            ? [
                TransitFieldReview(
                    field: .transitType,
                    reason: String(localized: "Review the automatically detected transit type.")
                ),
                TransitFieldReview(
                    field: .origin,
                    reason: String(localized: "Review the automatically detected origin.")
                ),
                TransitFieldReview(
                    field: .destination,
                    reason: String(localized: "Review the automatically detected destination.")
                ),
                TransitFieldReview(
                    field: .time,
                    reason: String(localized: "Review the automatically detected transit time.")
                ),
            ]
            : []
        let draft = ResolvedTransitDraft(
            transitType: motionKind.transitTypeName,
            originPlace: originPlace,
            originLocation: originLocation,
            originRawText: originName,
            destinationPlace: destinationPlace,
            destinationLocation: destinationLocation,
            destinationRawText: destinationName,
            startTime: candidate.startTime,
            endTime: endTime,
            timeConfidence: .explicit,
            people: [],
            durationSource: .unresolved,
            originCandidates: [],
            destinationCandidates: [],
            unresolvedPeople: [],
            fieldReviews: reviews
        )
        let entry = TransitEntryStore.makeEntry(draft: draft, rawInput: nil)
        entry.startTimeZoneIdentifier = originLocation.timeZoneIdentifier
            ?? candidate.timeZoneIdentifier
        entry.endTimeZoneIdentifier = destinationLocation.timeZoneIdentifier
            ?? candidate.timeZoneIdentifier
        return entry
    }
}

@MainActor
enum AutomationCandidateEntryService {
    @discardableResult
    static func synchronizePending(
        in modelContext: ModelContext
    ) throws -> Int {
        let candidates = try modelContext.fetch(
            FetchDescriptor<AutomationCandidate>(
                sortBy: [SortDescriptor(\.startTime)]
            )
        )
        var updatedProvenance = false
        for candidate in candidates
        where candidate.provenanceRecordedAt == nil {
            guard let entryID = candidate.acceptedEntryID else { continue }
            if let entry = try entry(withID: entryID, in: modelContext),
               entry.automationCandidateID == nil {
                entry.automationCandidateID = candidate.id
            }
            candidate.provenanceRecordedAt = .now
            updatedProvenance = true
        }
        let pendingCandidates = candidates.filter { candidate in
            guard candidate.status == .pending,
                  let endTime = candidate.endTime else { return false }
            return endTime > candidate.startTime
        }

        let places = pendingCandidates.isEmpty
            ? []
            : try modelContext.fetch(FetchDescriptor<Place>())
        var insertedCount = 0
        for candidate in pendingCandidates {
            if let entry = try entry(withID: candidate.id, in: modelContext) {
                if entry.automationCandidateID == nil {
                    entry.automationCandidateID = candidate.id
                    updatedProvenance = true
                }
                if candidate.provenanceRecordedAt == nil {
                    candidate.provenanceRecordedAt = .now
                    updatedProvenance = true
                }
                continue
            }
            guard let entry = AutomationCandidateEntryFactory.makeEntry(
                for: candidate,
                places: places,
                needsReview: true,
                id: candidate.id
            ) else { continue }
            modelContext.insert(entry)
            candidate.provenanceRecordedAt = .now
            insertedCount += 1
        }

        if insertedCount > 0 || updatedProvenance {
            try modelContext.save()
            NotificationCenter.default.post(
                name: .automationCandidatesDidChange,
                object: nil
            )
        }
        return insertedCount
    }

    private static func entry(
        withID id: UUID,
        in modelContext: ModelContext
    ) throws -> LogEntry? {
        var descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
