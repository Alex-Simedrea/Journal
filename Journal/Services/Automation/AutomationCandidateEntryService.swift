import Foundation
import SwiftData

nonisolated enum AutomationCandidateEntryFactory {
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

nonisolated enum AutomationCandidateEntryService {
    private static let boundarySnapThreshold: TimeInterval = 5 * 60

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
        let allEntries = try entriesNearPendingCandidates(
            pendingCandidates,
            in: modelContext
        )
        var entriesByID: [UUID: LogEntry] = [:]
        var entriesByCandidateID: [UUID: [LogEntry]] = [:]
        for entry in allEntries {
            entriesByID[entry.id] = entriesByID[entry.id] ?? entry
            if let candidateID = entry.automationCandidateID {
                entriesByCandidateID[candidateID, default: []].append(entry)
            }
        }
        let pendingCandidateIDs = Set(pendingCandidates.map(\.id))
        let establishedEntries = allEntries.filter { entry in
            guard !entry.needsReview else { return false }
            if pendingCandidateIDs.contains(entry.id) { return false }
            if let candidateID = entry.automationCandidateID,
               pendingCandidateIDs.contains(candidateID) {
                return false
            }
            return entry.startTime != nil && entry.endTime != nil
        }
        let snappedCandidateIDs = snapTimes(
            of: pendingCandidates,
            to: establishedEntries
        )

        let places = pendingCandidates.isEmpty
            ? []
            : try modelContext.fetch(FetchDescriptor<Place>())
        let placesByID = Dictionary(uniqueKeysWithValues: places.map {
            ($0.id, $0)
        })
        let canonicalizedCandidateIDs = canonicalizeTransitEndpoints(
            of: pendingCandidates,
            establishedEntries: establishedEntries,
            places: places,
            placesByID: placesByID
        )
        var insertedCount = 0
        var removedCount = 0
        var updatedTimelineEntry = false
        var entriesToDelete: [LogEntry] = []
        var entryIDsToDelete: Set<UUID> = []
        for candidate in pendingCandidates {
            var materializedEntries = entriesByCandidateID[candidate.id] ?? []
            if let sameIDEntry = entriesByID[candidate.id],
               !materializedEntries.contains(where: {
                   $0.id == sameIDEntry.id
               }) {
                materializedEntries.append(sameIDEntry)
            }
            materializedEntries.removeAll {
                entryIDsToDelete.contains($0.id)
            }
            if establishedEntries.contains(where: {
                substantiallyDuplicates(candidate, establishedEntry: $0)
            }) {
                for entry in materializedEntries {
                    if entryIDsToDelete.insert(entry.id).inserted {
                        entriesToDelete.append(entry)
                        removedCount += 1
                    }
                }
                continue
            }

            if let entry = preferredMaterializedEntry(
                from: materializedEntries,
                candidateID: candidate.id
            ) {
                for duplicate in materializedEntries where duplicate.id != entry.id {
                    if entryIDsToDelete.insert(duplicate.id).inserted {
                        entriesToDelete.append(duplicate)
                        removedCount += 1
                    }
                }
                if entry.automationCandidateID == nil {
                    entry.automationCandidateID = candidate.id
                    updatedProvenance = true
                }
                if candidate.provenanceRecordedAt == nil {
                    candidate.provenanceRecordedAt = .now
                    updatedProvenance = true
                }
                if entry.startTime != candidate.startTime
                    || entry.endTime != candidate.endTime {
                    entry.startTime = candidate.startTime
                    entry.endTime = candidate.endTime
                    updatedTimelineEntry = true
                }
                if refreshMaterializedLocations(
                    in: entry,
                    from: candidate,
                    placesByID: placesByID
                ) {
                    updatedTimelineEntry = true
                }
                try EntryLinkingService.propagateTimeEdit(
                    from: entry,
                    in: modelContext
                )
                switch entry.kind {
                case .transit:
                    try EntryLinkingService.propagateLocationEdit(
                        from: entry,
                        role: .origin,
                        in: modelContext
                    )
                    try EntryLinkingService.propagateLocationEdit(
                        from: entry,
                        role: .destination,
                        in: modelContext
                    )
                case .placeVisit:
                    try EntryLinkingService.propagateLocationEdit(
                        from: entry,
                        role: .place,
                        in: modelContext
                    )
                case .workout, .wakeUp:
                    break
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

        for entry in entriesToDelete {
            modelContext.delete(entry)
        }

        let linksChanged = try EntryLinkingService.reconcile(in: modelContext)

        if insertedCount > 0 || removedCount > 0 || updatedProvenance
            || updatedTimelineEntry || !snappedCandidateIDs.isEmpty
            || !canonicalizedCandidateIDs.isEmpty || linksChanged {
            try modelContext.save()
            NotificationCenter.default.post(
                name: .automationCandidatesDidChange,
                object: nil
            )
        }
        return insertedCount
    }

    private static func preferredMaterializedEntry(
        from entries: [LogEntry],
        candidateID: UUID
    ) -> LogEntry? {
        entries.first { $0.id == candidateID } ?? entries.first
    }

    private enum EndpointRole {
        case arrival
        case departure
    }

    private struct SavedPlaceAnchor {
        let date: Date
        let role: EndpointRole
        let placeID: UUID
    }

    @discardableResult
    private static func canonicalizeTransitEndpoints(
        of candidates: [AutomationCandidate],
        establishedEntries: [LogEntry],
        places: [Place],
        placesByID: [UUID: Place]
    ) -> Set<UUID> {
        guard !places.isEmpty else { return [] }
        let anchors = savedPlaceAnchors(
            candidates: candidates,
            establishedEntries: establishedEntries
        )
        var changedCandidateIDs: Set<UUID> = []

        for candidate in candidates where candidate.kind == .transit {
            var changed = false
            if let originLocation = candidate.originLocation,
               let place = canonicalPlace(
                    explicitID: candidate.originPlaceID,
                    location: originLocation,
                    date: candidate.startTime,
                    role: .departure,
                    anchors: anchors,
                    places: places,
                    placesByID: placesByID
               ), candidate.originPlaceID != place.id
                    || candidate.originLocation != place.location {
                candidate.originPlaceID = place.id
                candidate.originLocation = place.location
                candidate.timeZoneIdentifier = place.location
                    .timeZoneIdentifier ?? candidate.timeZoneIdentifier
                changed = true
            }

            if let endTime = candidate.endTime,
               let destinationLocation = candidate.destinationLocation,
               let place = canonicalPlace(
                    explicitID: candidate.destinationPlaceID,
                    location: destinationLocation,
                    date: endTime,
                    role: .arrival,
                    anchors: anchors,
                    places: places,
                    placesByID: placesByID
               ), candidate.destinationPlaceID != place.id
                    || candidate.destinationLocation != place.location {
                candidate.destinationPlaceID = place.id
                candidate.destinationLocation = place.location
                changed = true
            }

            if changed {
                candidate.updatedAt = .now
                changedCandidateIDs.insert(candidate.id)
            }
        }
        return changedCandidateIDs
    }

    private static func canonicalPlace(
        explicitID: UUID?,
        location: Location,
        date: Date,
        role: EndpointRole,
        anchors: [SavedPlaceAnchor],
        places: [Place],
        placesByID: [UUID: Place]
    ) -> Place? {
        if let explicitID, let place = placesByID[explicitID] {
            return place
        }
        let matchingAnchor = anchors
            .filter {
                $0.role == role
                    && abs($0.date.timeIntervalSince(date))
                        <= boundarySnapThreshold
            }
            .min(by: {
                let left = abs($0.date.timeIntervalSince(date))
                let right = abs($1.date.timeIntervalSince(date))
                if left == right {
                    return $0.placeID.uuidString < $1.placeID.uuidString
                }
                return left < right
            })
        if let matchingAnchor,
           let place = placesByID[matchingAnchor.placeID] {
            return place
        }

        let coordinate = WorkoutCoordinateSnapshot(
            latitude: location.latitude,
            longitude: location.longitude,
            horizontalAccuracyMeters: 0
        )
        if case .matched(let place) = WorkoutPlaceMatcher.match(
            coordinate: coordinate,
            places: places
        ) {
            return place
        }
        return nil
    }

    private static func savedPlaceAnchors(
        candidates: [AutomationCandidate],
        establishedEntries: [LogEntry]
    ) -> [SavedPlaceAnchor] {
        var anchors: [SavedPlaceAnchor] = []
        for candidate in candidates {
            switch candidate.kind {
            case .visit:
                guard let placeID = candidate.visitPlaceID else { continue }
                anchors.append(.init(
                    date: candidate.startTime,
                    role: .arrival,
                    placeID: placeID
                ))
                if let endTime = candidate.endTime {
                    anchors.append(.init(
                        date: endTime,
                        role: .departure,
                        placeID: placeID
                    ))
                }
            case .transit:
                if let placeID = candidate.originPlaceID {
                    anchors.append(.init(
                        date: candidate.startTime,
                        role: .departure,
                        placeID: placeID
                    ))
                }
                if let endTime = candidate.endTime,
                   let placeID = candidate.destinationPlaceID {
                    anchors.append(.init(
                        date: endTime,
                        role: .arrival,
                        placeID: placeID
                    ))
                }
            }
        }

        for entry in establishedEntries {
            guard let startTime = entry.startTime,
                  let endTime = entry.endTime else { continue }
            switch entry.kind {
            case .placeVisit:
                guard let placeID = entry.placeVisitDetails?.place?.id else {
                    continue
                }
                anchors.append(.init(
                    date: startTime,
                    role: .arrival,
                    placeID: placeID
                ))
                anchors.append(.init(
                    date: endTime,
                    role: .departure,
                    placeID: placeID
                ))
            case .transit:
                if let placeID = entry.transitDetails?.originPlace?.id {
                    anchors.append(.init(
                        date: startTime,
                        role: .departure,
                        placeID: placeID
                    ))
                }
                if let placeID = entry.transitDetails?.destinationPlace?.id {
                    anchors.append(.init(
                        date: endTime,
                        role: .arrival,
                        placeID: placeID
                    ))
                }
            case .workout:
                let details = entry.workoutDetails
                if details?.movementKind == .moving {
                    if let placeID = details?.originPlace?.id {
                        anchors.append(.init(
                            date: startTime,
                            role: .departure,
                            placeID: placeID
                        ))
                    }
                    if let placeID = details?.destinationPlace?.id {
                        anchors.append(.init(
                            date: endTime,
                            role: .arrival,
                            placeID: placeID
                        ))
                    }
                } else if let placeID = details?.place?.id {
                    anchors.append(.init(
                        date: startTime,
                        role: .arrival,
                        placeID: placeID
                    ))
                    anchors.append(.init(
                        date: endTime,
                        role: .departure,
                        placeID: placeID
                    ))
                }
            case .wakeUp:
                continue
            }
        }
        return anchors
    }

    private static func refreshMaterializedLocations(
        in entry: LogEntry,
        from candidate: AutomationCandidate,
        placesByID: [UUID: Place]
    ) -> Bool {
        switch candidate.kind {
        case .visit:
            guard let placeID = candidate.visitPlaceID,
                  let place = placesByID[placeID],
                  let details = entry.placeVisitDetails,
                  details.place == nil else { return false }
            details.place = place
            details.location = place.location
            details.placeRawText = place.name
            entry.startTimeZoneIdentifier = place.location.timeZoneIdentifier
                ?? entry.startTimeZoneIdentifier
            entry.endTimeZoneIdentifier = entry.startTimeZoneIdentifier
            return true
        case .transit:
            guard let details = entry.transitDetails else { return false }
            var changed = false
            if details.originPlace == nil,
               let placeID = candidate.originPlaceID,
               let place = placesByID[placeID] {
                details.originPlace = place
                details.originLocation = place.location
                details.originRawText = place.name
                entry.startTimeZoneIdentifier = place.location
                    .timeZoneIdentifier ?? entry.startTimeZoneIdentifier
                changed = true
            }
            if details.destinationPlace == nil,
               let placeID = candidate.destinationPlaceID,
               let place = placesByID[placeID] {
                details.destinationPlace = place
                details.destinationLocation = place.location
                details.destinationRawText = place.name
                entry.endTimeZoneIdentifier = place.location
                    .timeZoneIdentifier ?? entry.endTimeZoneIdentifier
                changed = true
            }
            return changed
        }
    }

    @discardableResult
    private static func snapTimes(
        of candidates: [AutomationCandidate],
        to establishedEntries: [LogEntry]
    ) -> Set<UUID> {
        var changedCandidateIDs: Set<UUID> = []
        var establishedStartAnchors: Set<UUID> = []
        var establishedEndAnchors: Set<UUID> = []
        let establishedStarts = establishedEntries.compactMap(\.startTime).sorted()
        let establishedEnds = establishedEntries.compactMap(\.endTime).sorted()

        for candidate in candidates {
            if let snappedStart = nearestDate(
                to: candidate.startTime,
                in: establishedEnds
            ), updateStart(candidate, to: snappedStart) {
                changedCandidateIDs.insert(candidate.id)
                establishedStartAnchors.insert(candidate.id)
            }
            if let endTime = candidate.endTime,
               let snappedEnd = nearestDate(to: endTime, in: establishedStarts),
               updateEnd(candidate, to: snappedEnd) {
                changedCandidateIDs.insert(candidate.id)
                establishedEndAnchors.insert(candidate.id)
            }
        }

        let chronological = candidates.sorted {
            if $0.startTime == $1.startTime { return $0.id.uuidString < $1.id.uuidString }
            return $0.startTime < $1.startTime
        }
        for pairIndex in chronological.indices.dropLast() {
            let earlier = chronological[pairIndex]
            let later = chronological[chronological.index(after: pairIndex)]
            guard let earlierEnd = earlier.endTime,
                  abs(later.startTime.timeIntervalSince(earlierEnd))
                    <= boundarySnapThreshold else {
                continue
            }

            let earlierIsAnchored = establishedEndAnchors.contains(earlier.id)
            let laterIsAnchored = establishedStartAnchors.contains(later.id)
            if earlierIsAnchored {
                if updateStart(later, to: earlierEnd) {
                    changedCandidateIDs.insert(later.id)
                }
            } else if laterIsAnchored {
                if updateEnd(earlier, to: later.startTime) {
                    changedCandidateIDs.insert(earlier.id)
                }
            } else if earlier.kind == .transit && later.kind == .visit {
                if updateStart(later, to: earlierEnd) {
                    changedCandidateIDs.insert(later.id)
                }
            } else if earlier.kind == .visit && later.kind == .transit {
                if updateEnd(earlier, to: later.startTime) {
                    changedCandidateIDs.insert(earlier.id)
                }
            } else if updateStart(later, to: earlierEnd) {
                changedCandidateIDs.insert(later.id)
            }
        }

        for candidate in candidates where changedCandidateIDs.contains(candidate.id) {
            candidate.updatedAt = .now
        }
        return changedCandidateIDs
    }

    private static func nearestDate(
        to target: Date,
        in dates: [Date]
    ) -> Date? {
        guard !dates.isEmpty else { return nil }

        var lowerBound = 0
        var upperBound = dates.count
        while lowerBound < upperBound {
            let midpoint = lowerBound + (upperBound - lowerBound) / 2
            if dates[midpoint] < target {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        let neighboringIndices = [lowerBound - 1, lowerBound]
            .filter { dates.indices.contains($0) }
        return neighboringIndices
            .map { dates[$0] }
            .filter {
                abs($0.timeIntervalSince(target)) <= boundarySnapThreshold
            }
            .min {
                let firstDistance = abs($0.timeIntervalSince(target))
                let secondDistance = abs($1.timeIntervalSince(target))
                if firstDistance == secondDistance { return $0 < $1 }
                return firstDistance < secondDistance
            }
    }

    private static func updateStart(
        _ candidate: AutomationCandidate,
        to date: Date
    ) -> Bool {
        guard candidate.startTime != date,
              candidate.endTime.map({ date < $0 }) ?? true else { return false }
        candidate.startTime = date
        return true
    }

    private static func updateEnd(
        _ candidate: AutomationCandidate,
        to date: Date
    ) -> Bool {
        guard candidate.endTime != date, date > candidate.startTime else {
            return false
        }
        candidate.endTime = date
        return true
    }

    private static func substantiallyDuplicates(
        _ candidate: AutomationCandidate,
        establishedEntry entry: LogEntry
    ) -> Bool {
        guard compatible(candidate: candidate, entry: entry),
              let candidateEnd = candidate.endTime,
              let entryStart = entry.startTime,
              let entryEnd = entry.endTime,
              candidateEnd > candidate.startTime,
              entryEnd > entryStart else { return false }

        let overlapStart = max(candidate.startTime, entryStart)
        let overlapEnd = min(candidateEnd, entryEnd)
        let overlap = overlapEnd.timeIntervalSince(overlapStart)
        let shorterDuration = min(
            candidateEnd.timeIntervalSince(candidate.startTime),
            entryEnd.timeIntervalSince(entryStart)
        )
        return overlap >= 60 && overlap / shorterDuration >= 0.5
    }

    private static func compatible(
        candidate: AutomationCandidate,
        entry: LogEntry
    ) -> Bool {
        switch (candidate.kind, entry.kind) {
        case (.transit, .transit), (.visit, .placeVisit):
            true
        case (.transit, .workout):
            entry.workoutDetails?.movementKind == .moving
        case (.visit, .workout):
            entry.workoutDetails?.movementKind == .staticWorkout
        default:
            false
        }
    }

    private static func entriesNearPendingCandidates(
        _ candidates: [AutomationCandidate],
        in modelContext: ModelContext
    ) throws -> [LogEntry] {
        guard let earliestStart = candidates.map(\.startTime).min(),
              let latestEnd = candidates.compactMap(\.endTime).max() else {
            return []
        }
        let lowerBound = earliestStart.addingTimeInterval(
            -boundarySnapThreshold
        )
        let upperBound = latestEnd.addingTimeInterval(boundarySnapThreshold)
        let predicate = #Predicate<LogEntry> { entry in
            (entry.startTime ?? upperBound) < upperBound
                && (entry.endTime ?? lowerBound) > lowerBound
        }
        return try modelContext.fetch(
            FetchDescriptor<LogEntry>(predicate: predicate)
        )
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
