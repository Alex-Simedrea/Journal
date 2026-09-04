import Foundation
import SwiftData

/// Owns the model context used by launch and foreground maintenance.
///
/// Instances are created by `JournalPersistenceActors` from detached
/// execution. This matters because SwiftData chooses the model context's
/// executor when a model actor is initialized.
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
            try modelContext.save()
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
}
