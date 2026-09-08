import Foundation
import SwiftData

/// Performs detection, enrichment, and synchronization work on a dedicated
/// background executor. Models fetched here never leave the actor: every
/// operation works on IDs and value snapshots across suspension points,
/// re-fetches its targets afterwards, and saves through
/// `JournalPersistence.save` so a failure cannot leave staged mutations.
@ModelActor
actor JournalBackgroundMaintenance {
#if DEBUG
    func executorUsesMainThreadForTesting() -> Bool {
        Thread.isMainThread
    }
#endif

    func persistVisit(_ snapshot: VisitDetectionSnapshot) {
        do {
            guard try AutomationCandidateStore.upsertVisit(
                snapshot,
                in: modelContext
            ) != nil else { return }
            try JournalPersistence.save(modelContext)
            NotificationCenter.default.post(
                name: .automationCandidatesDidChange,
                object: nil
            )
        } catch {
            modelContext.rollback()
            print("Visit persistence failed: \(error)")
        }
    }

    func persistMotion(_ segments: [MotionActivitySegment]) {
        do {
            try MotionTransitDetectionService.persist(
                segments: segments,
                in: modelContext
            )
        } catch {
            modelContext.rollback()
            print("Motion activity persistence failed: \(error)")
        }
    }

    func synchronizeDetections(
        motionSegments: [MotionActivitySegment]
    ) async {
        do {
            try await VisitMonitoringCoordinator.enrichClosedVisits(
                in: modelContext
            )
        } catch {
            print("Visit enrichment failed: \(error)")
        }

        do {
            try MotionTransitDetectionService.persist(
                segments: motionSegments,
                in: modelContext
            )
        } catch {
            print("Motion activity synchronization failed: \(error)")
        }

    }

    func synchronizeCandidates() {
        do {
            try AutomationCandidateEntryService.synchronizePending(
                in: modelContext
            )
        } catch {
            print("Candidate timeline synchronization failed: \(error)")
        }
    }

    func synchronizePhotos() async {
        do {
            try await PhotoAutoLinkService.synchronize(in: modelContext)
        } catch {
            print("Automatic photo linking failed: \(error)")
        }
    }

    func populateTransitDistance(entryID: UUID) async {
        await TransitDistanceService.populate(
            entryID: entryID,
            in: modelContext
        )
    }

    func populateEntryEnrichment() async {
        do {
            try EntryLinkingService.reconcileAndSave(in: modelContext)
        } catch {
            print("Entry link reconciliation failed: \(error)")
        }
        await EntryWeatherService.populateMissing(in: modelContext)
        await TransitDistanceService.populateMissing(in: modelContext)
        await LocationGeographyService.populateMissing(in: modelContext)
    }

    func refreshEntryWeather(entryID: UUID) async {
        await EntryWeatherService.populateEndpoints(
            entryID: entryID,
            in: modelContext,
            force: true
        )
    }

    /// Post-creation enrichment for a single accepted or composed entry.
    func enrichNewEntry(
        entryID: UUID,
        includesWeather: Bool = true,
        includesDistance: Bool = false
    ) async {
        if includesWeather {
            _ = try? await EntryWeatherService.populate(
                entryID: entryID,
                in: modelContext
            )
        }
        if includesDistance {
            await TransitDistanceService.populate(
                entryID: entryID,
                in: modelContext
            )
        }
        await synchronizePhotos()
    }

    func synchronizeContacts() async throws {
        _ = try await ContactPersonSyncService.synchronizeAllContacts(
            in: modelContext
        )
    }
}
