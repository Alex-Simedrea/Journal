import CoreLocation
import Foundation
import OSLog
import SwiftData

nonisolated enum JournalRecordingFinalization: Sendable, Equatable {
    case visit
    case transit(RecordedTransitMode)
    case batch(entries: Int, visits: Int, transits: Int)
    case noUsableLocation
}

@MainActor
final class JournalRecordingFinalizer {
    private let motionService = JournalRecordingMotionService()
    private var locationResolutionCache: [String: Location] = [:]

    func finalize(
        _ recording: ActiveJournalRecording,
        in modelContext: ModelContext
    ) async throws -> JournalRecordingFinalization {
        let existing = try existingEntries(
            for: recording.id,
            in: modelContext
        )
        if !existing.isEmpty {
            return finalization(for: existing, mode: recording.mode)
        }
        locationResolutionCache.removeAll(keepingCapacity: true)

        let endedAt = recording.endedAt ?? .now
        let motion: [RecordedMotionObservation]
        do {
            motion = try await motionService.observations(
                from: recording.startedAt,
                to: endedAt
            )
        } catch {
            motion = []
            JournalRecordingLog.motion.error(
                "[Motion] history query failed: \(error.localizedDescription)"
            )
        }
        JournalRecordingLog.motion.info(
            "[Motion] queried \(recording.startedAt) → \(endedAt); \(motion.count) observations"
        )

        let places = try modelContext.fetch(FetchDescriptor<Place>())
        let regions = placeRegions(places)
        if recording.mode == .continuous {
            return try await finalizeContinuous(
                recording,
                motion: motion,
                places: places,
                regions: regions,
                in: modelContext
            )
        }
        return try await finalizeSingle(
            recording,
            motion: motion,
            places: places,
            regions: regions,
            in: modelContext
        )
    }

    private func finalizeSingle(
        _ recording: ActiveJournalRecording,
        motion: [RecordedMotionObservation],
        places: [Place],
        regions: [JournalRecordingPlaceRegion],
        in modelContext: ModelContext
    ) async throws -> JournalRecordingFinalization {
        guard let classification = JournalRecordingClassifier.classify(
            points: recording.points,
            motion: motion,
            placeRegions: regions
        ) else {
            return .noUsableLocation
        }
        let endedAt = recording.endedAt ?? .now
        let entry: LogEntry
        let result: JournalRecordingFinalization
        switch classification {
        case .visit(let coordinate, let radius):
            JournalRecordingLog.classifier.info(
                "[Classifier] visit; coverage radius \(radius)m"
            )
            let place = matchedPlace(
                at: coordinate,
                horizontalAccuracy: max(15, radius),
                places: places
            )
            entry = await makeVisitEntry(
                recordingID: recording.id,
                startTime: recording.startedAt,
                endTime: endedAt,
                coordinate: coordinate,
                place: place
            )
            result = .visit

        case .transit(
            let origin,
            let destination,
            let route,
            let distanceMeters,
            let mode
        ):
            JournalRecordingLog.classifier.info(
                "[Classifier] transit; \(distanceMeters)m; dominant mode \(mode.rawValue)"
            )
            entry = await makeTransitEntry(
                recordingID: recording.id,
                startTime: recording.startedAt,
                endTime: endedAt,
                origin: origin,
                destination: destination,
                originPlace: matchedPlace(
                    at: origin,
                    horizontalAccuracy: 25,
                    places: places
                ),
                destinationPlace: matchedPlace(
                    at: destination,
                    horizontalAccuracy: 25,
                    places: places
                ),
                route: route,
                distanceMeters: distanceMeters,
                mode: mode,
                motion: motion
            )
            result = .transit(mode)
        }
        modelContext.insert(entry)
        _ = try EntryLinkingService.reconcile(in: modelContext)
        try modelContext.save()
        return result
    }

    private func finalizeContinuous(
        _ recording: ActiveJournalRecording,
        motion: [RecordedMotionObservation],
        places: [Place],
        regions: [JournalRecordingPlaceRegion],
        in modelContext: ModelContext
    ) async throws -> JournalRecordingFinalization {
        let endedAt = recording.endedAt ?? .now
        let visitEvidence = try visitEvidence(
            from: recording.startedAt,
            to: endedAt,
            in: modelContext
        )
        JournalRecordingLog.classifier.info(
            "[Classifier] fusing \(recording.points.count) GPS points, \(motion.count) motion observations, and \(visitEvidence.count) visit observations"
        )
        let segments = JournalRecordingSegmenter.segments(
            points: recording.points,
            motion: motion,
            places: regions,
            visitEvidence: visitEvidence
        )
        guard !segments.isEmpty else { return .noUsableLocation }
        let placesByID = Dictionary(uniqueKeysWithValues: places.map {
            ($0.id, $0)
        })
        var entries: [LogEntry] = []
        var visitCount = 0
        var transitCount = 0

        for segment in segments {
            switch segment {
            case .visit(let visit):
                entries.append(
                    await makeVisitEntry(
                        recordingID: recording.id,
                        startTime: visit.startTime,
                        endTime: visit.endTime,
                        coordinate: visit.coordinate,
                        place: visit.placeID.flatMap { placesByID[$0] }
                    )
                )
                visitCount += 1
            case .transit(let transit):
                entries.append(
                    await makeTransitEntry(
                        recordingID: recording.id,
                        startTime: transit.startTime,
                        endTime: transit.endTime,
                        origin: transit.origin,
                        destination: transit.destination,
                        originPlace: transit.originPlaceID.flatMap {
                            placesByID[$0]
                        },
                        destinationPlace: transit.destinationPlaceID.flatMap {
                            placesByID[$0]
                        },
                        route: transit.route,
                        distanceMeters: transit.distanceMeters,
                        mode: transit.mode,
                        motion: transit.motion
                    )
                )
                transitCount += 1
            }
        }

        for entry in entries {
            modelContext.insert(entry)
        }
        _ = try EntryLinkingService.reconcile(in: modelContext)
        try modelContext.save()
        do {
            // The passive timeline automation may have materialized review
            // drafts for the same CLVisit/motion observations. Reconcile now
            // that the richer recording entries are established, so those
            // drafts do not appear as duplicates.
            _ = try AutomationCandidateEntryService.synchronizePending(
                in: modelContext
            )
        } catch {
            JournalRecordingLog.recording.error(
                "[Recording] automation draft reconciliation failed: \(error.localizedDescription)"
            )
        }
        JournalRecordingLog.recording.info(
            "[Recording] finalized continuous session into \(entries.count) entries"
        )
        return .batch(
            entries: entries.count,
            visits: visitCount,
            transits: transitCount
        )
    }

    private func makeVisitEntry(
        recordingID: UUID,
        startTime: Date,
        endTime: Date,
        coordinate: RecordedRoutePoint,
        place: Place?
    ) async -> LogEntry {
        let location = await resolvedLocation(for: coordinate, place: place)
        let draft = ResolvedPlaceVisitDraft(
            place: place,
            location: location,
            startTime: startTime,
            endTime: endTime,
            timeConfidence: .explicit,
            people: [],
            candidates: [],
            unresolvedPeople: [],
            fieldReviews: [],
            entryKindReviewReason: nil
        )
        let entry = PlaceVisitEntryStore.makeEntry(
            draft: draft,
            rawInput: String(localized: "Recorded journal session")
        )
        entry.journalRecordingID = recordingID
        return entry
    }

    private func makeTransitEntry(
        recordingID: UUID,
        startTime: Date,
        endTime: Date,
        origin: RecordedRoutePoint,
        destination: RecordedRoutePoint,
        originPlace: Place?,
        destinationPlace: Place?,
        route: [RecordedRoutePoint],
        distanceMeters: Double,
        mode: RecordedTransitMode,
        motion: [RecordedMotionObservation]
    ) async -> LogEntry {
        async let resolvedOrigin = resolvedLocation(
            for: origin,
            place: originPlace
        )
        async let resolvedDestination = resolvedLocation(
            for: destination,
            place: destinationPlace
        )
        var fieldReviews: [TransitFieldReview] = []
        if mode == .unknown {
            fieldReviews.append(
                TransitFieldReview(
                    field: .transitType,
                    reason: String(
                        localized: "The recording did not contain enough motion information to identify transportation."
                    )
                )
            )
        }
        let draft = await ResolvedTransitDraft(
            transitType: mode.transitTypeName,
            originPlace: originPlace,
            originLocation: resolvedOrigin,
            destinationPlace: destinationPlace,
            destinationLocation: resolvedDestination,
            startTime: startTime,
            endTime: endTime,
            timeConfidence: .explicit,
            people: [],
            durationSource: .unresolved,
            originCandidates: [],
            destinationCandidates: [],
            unresolvedPeople: [],
            fieldReviews: fieldReviews
        )
        let entry = TransitEntryStore.makeEntry(
            draft: draft,
            rawInput: String(localized: "Recorded journal session")
        )
        entry.journalRecordingID = recordingID
        entry.transitDetails?.distanceMeters = distanceMeters
        entry.transitDetails?.recordedRoute = route
        entry.transitDetails?.recordedMotion = motion
        entry.transitDetails?.recordedTransitMode = mode
        return entry
    }

    private func resolvedLocation(
        for point: RecordedRoutePoint,
        place: Place?
    ) async -> Location {
        if let place { return place.location }
        let cacheKey = String(
            format: "%.4f,%.4f",
            point.latitude,
            point.longitude
        )
        if let cached = locationResolutionCache[cacheKey] { return cached }
        let location = await LocationService.shared.location(
            at: CLLocationCoordinate2D(
                latitude: point.latitude,
                longitude: point.longitude
            )
        )
        locationResolutionCache[cacheKey] = location
        return location
    }

    private func placeRegions(_ places: [Place]) -> [JournalRecordingPlaceRegion] {
        places.map { place in
            JournalRecordingPlaceRegion(
                id: place.id,
                name: place.name,
                latitude: place.location.latitude,
                longitude: place.location.longitude,
                radiusMeters: place.accuracyRadiusMeters,
                isHome: GuidedComposerLocationRanking.isHomeName(place.name)
            )
        }
    }

    private func matchedPlace(
        at point: RecordedRoutePoint,
        horizontalAccuracy: Double,
        places: [Place]
    ) -> Place? {
        let coordinate = WorkoutCoordinateSnapshot(
            latitude: point.latitude,
            longitude: point.longitude,
            horizontalAccuracyMeters: horizontalAccuracy
        )
        guard case .matched(let place) = WorkoutPlaceMatcher.match(
            coordinate: coordinate,
            places: places
        ) else { return nil }
        return place
    }

    private func existingEntries(
        for recordingID: UUID,
        in modelContext: ModelContext
    ) throws -> [LogEntry] {
        try modelContext.fetch(
            FetchDescriptor<LogEntry>(
                predicate: #Predicate { entry in
                    entry.journalRecordingID == recordingID
                },
                sortBy: [SortDescriptor(\.startTime)]
            )
        )
    }

    private func visitEvidence(
        from startTime: Date,
        to endTime: Date,
        in modelContext: ModelContext
    ) throws -> [JournalRecordingVisitEvidence] {
        // CLVisit candidates are supporting evidence, not authoritative output.
        // The segmenter validates every candidate against the denser recorded
        // GPS trace before it is allowed to form or extend a visit.
        try modelContext.fetch(FetchDescriptor<AutomationCandidate>())
            .compactMap { candidate in
                guard candidate.kind == .visit,
                      candidate.status != .dismissed,
                      let candidateEnd = candidate.endTime,
                      candidateEnd > startTime,
                      candidate.startTime < endTime,
                      let location = candidate.visitLocation else {
                    return nil
                }
                let clippedStart = max(startTime, candidate.startTime)
                let clippedEnd = min(endTime, candidateEnd)
                guard clippedEnd > clippedStart else { return nil }
                return JournalRecordingVisitEvidence(
                    startTime: clippedStart,
                    endTime: clippedEnd,
                    latitude: location.latitude,
                    longitude: location.longitude,
                    horizontalAccuracyMeters: max(
                        0,
                        candidate.visitHorizontalAccuracyMeters ?? 100
                    ),
                    placeID: candidate.visitPlaceID
                )
            }
    }

    private func finalization(
        for entries: [LogEntry],
        mode: JournalRecordingMode
    ) -> JournalRecordingFinalization {
        if mode == .continuous || entries.count > 1 {
            return .batch(
                entries: entries.count,
                visits: entries.count { $0.kind == .placeVisit },
                transits: entries.count { $0.kind == .transit }
            )
        }
        guard let entry = entries.first else { return .noUsableLocation }
        return entry.kind == .placeVisit
            ? .visit
            : .transit(entry.transitDetails?.recordedTransitMode ?? .unknown)
    }
}
