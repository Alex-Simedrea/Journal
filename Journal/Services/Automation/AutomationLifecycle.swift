import CoreLocation
import CoreMotion
import Foundation
import Observation
import Photos
import SwiftData
import UIKit

extension Notification.Name {
    static let automationCandidatesDidChange = Notification.Name(
        "journal.automationCandidatesDidChange"
    )
}

@MainActor
enum JournalModelContainer {
    static let shared: ModelContainer = {
        do {
            let configuration = ModelConfiguration()
            // This is deliberately checked on every cold launch. It is a
            // small, idempotent repair and protects against a relationship
            // row disappearing after any interrupted edit, not just during a
            // one-time automation migration.
            _ = try SwiftDataStoreIntegrityRepair
                .clearDanglingEntryDetailReferences(
                    at: configuration.url
                )
            let container = try ModelContainer(
                for: LogEntry.self,
                Person.self,
                Place.self,
                TransitDetails.self,
                PlaceVisitDetails.self,
                WorkoutDetails.self,
                TransitType.self,
                AutomationCandidate.self,
                ActiveJournalRecording.self,
                configurations: configuration
            )
            try AutomationCandidateStoreRepair.runIfNeeded(
                in: container.mainContext
            )
            return container
        } catch {
            fatalError("Unable to create Journal model container: \(error)")
        }
    }()
}

@MainActor
enum AutomationCandidateStoreRepair {
    private static let repairVersion = 2
    private static let repairVersionKey =
        "journal.automation-candidate-store-repair-version"

    static var isNeeded: Bool {
        UserDefaults.standard.integer(forKey: repairVersionKey) < repairVersion
    }

    static func runIfNeeded(in modelContext: ModelContext) throws {
        guard isNeeded else { return }

        try rebuildNonAcceptedEntries(in: modelContext)
        try repairAcceptedEntries(in: modelContext)
        UserDefaults.standard.set(repairVersion, forKey: repairVersionKey)
    }

    static func rebuildNonAcceptedEntries(
        in modelContext: ModelContext
    ) throws {
        let candidates = try modelContext.fetch(
            FetchDescriptor<AutomationCandidate>()
        )
        let candidateIDs = candidates.compactMap { candidate in
            candidate.status == .accepted ? nil : candidate.id
        }

        for candidateID in candidateIDs {
            try modelContext.delete(
                model: LogEntry.self,
                where: #Predicate {
                    $0.id == candidateID
                        || $0.automationCandidateID == candidateID
                }
            )
        }
        try modelContext.save()
        try AutomationCandidateEntryService.synchronizePending(
            in: modelContext
        )
    }

    static func repairAcceptedEntries(
        in modelContext: ModelContext
    ) throws {
        let candidates = try modelContext.fetch(
            FetchDescriptor<AutomationCandidate>()
        ).filter { $0.status == .accepted }
        guard !candidates.isEmpty else { return }

        let entries = try modelContext.fetch(FetchDescriptor<LogEntry>())
        let places = try modelContext.fetch(FetchDescriptor<Place>())

        for candidate in candidates {
            let matchingEntries = entries.filter {
                $0.id == candidate.id
                    || $0.automationCandidateID == candidate.id
                    || $0.id == candidate.acceptedEntryID
            }
            guard let entry = preferredEntry(
                from: matchingEntries,
                for: candidate
            ) else { continue }

            entry.automationCandidateID = candidate.id
            candidate.acceptedEntryID = entry.id
            try removeDuplicates(
                matchingEntries.filter { $0.id != entry.id },
                in: modelContext
            )
            restoreMissingDetails(
                for: entry,
                from: candidate,
                places: places,
                in: modelContext
            )
        }
        try modelContext.save()
    }

    private static func preferredEntry(
        from entries: [LogEntry],
        for candidate: AutomationCandidate
    ) -> LogEntry? {
        if let acceptedEntryID = candidate.acceptedEntryID,
           let accepted = entries.first(where: { $0.id == acceptedEntryID }) {
            return accepted
        }
        return entries.first(where: { $0.id == candidate.id })
            ?? entries.first
    }

    private static func removeDuplicates(
        _ entries: [LogEntry],
        in modelContext: ModelContext
    ) throws {
        guard !entries.isEmpty else { return }

        // Detach first so deleting a duplicate can never cascade through a
        // child-detail object that another historical copy also references.
        for entry in entries {
            entry.transitDetails = nil
            entry.placeVisitDetails = nil
            entry.workoutDetails = nil
        }
        try modelContext.save()
        for entry in entries {
            modelContext.delete(entry)
        }
        try modelContext.save()
    }

    private static func restoreMissingDetails(
        for entry: LogEntry,
        from candidate: AutomationCandidate,
        places: [Place],
        in modelContext: ModelContext
    ) {
        switch entry.kind {
        case .placeVisit where entry.placeVisitDetails == nil:
            guard let location = candidate.visitLocation else { return }
            let place = places.first { $0.id == candidate.visitPlaceID }
            let name = place?.name ?? location.preferredName
            let details = PlaceVisitDetails(
                place: place,
                location: (place?.location ?? location)
                    .withFallbackDisplayName(name),
                placeRawText: name
            )
            modelContext.insert(details)
            entry.placeVisitDetails = details
        case .transit where entry.transitDetails == nil:
            guard let origin = candidate.originLocation,
                  let destination = candidate.destinationLocation else {
                return
            }
            let originPlace = places.first { $0.id == candidate.originPlaceID }
            let destinationPlace = places.first {
                $0.id == candidate.destinationPlaceID
            }
            let originName = originPlace?.name ?? origin.preferredName
            let destinationName = destinationPlace?.name
                ?? destination.preferredName
            let details = TransitDetails(
                type: candidate.motionKind?.transitTypeName ?? "Transit",
                originPlace: originPlace,
                originLocation: (originPlace?.location ?? origin)
                    .withFallbackDisplayName(originName),
                originRawText: originName,
                destinationPlace: destinationPlace,
                destinationLocation: (destinationPlace?.location ?? destination)
                    .withFallbackDisplayName(destinationName),
                destinationRawText: destinationName
            )
            modelContext.insert(details)
            entry.transitDetails = details
        default:
            break
        }
    }
}

@MainActor
final class JournalAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [
            UIApplication.LaunchOptionsKey: Any
        ]? = nil
    ) -> Bool {
        guard AutomationCoordinator.isEnabledForCurrentProcess else {
            return true
        }
        VisitMonitoringCoordinator.shared.configure(
            modelContainer: JournalModelContainer.shared
        )
        VisitMonitoringCoordinator.shared.resumeIfAuthorized()
        JournalRecordingCoordinator.shared.restoreIfNeeded(
            applicationIsActive: application.applicationState == .active
        )
        return true
    }
}

enum AutomationPermissionState: Equatable {
    case notDetermined
    case allowed
    case limited
    case denied
    case unavailable

    var title: LocalizedStringResource {
        switch self {
        case .notDetermined: "Not requested"
        case .allowed: "Allowed"
        case .limited: "Limited"
        case .denied: "Denied"
        case .unavailable: "Unavailable"
        }
    }
}

@MainActor
@Observable
final class AutomationCoordinator {
    static let shared = AutomationCoordinator()
    static var isEnabledForCurrentProcess: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]
            == nil
    }

    private(set) var photoPermission = AutomationPermissionState
        .notDetermined
    private(set) var motionPermission = AutomationPermissionState
        .notDetermined
    private(set) var locationPermission = AutomationPermissionState
        .notDetermined
    private(set) var isSynchronizing = false

    private init() {
        refreshPermissionStates()
    }

    func start(in modelContext: ModelContext) async {
        guard Self.isEnabledForCurrentProcess else { return }
        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer {
            isSynchronizing = false
            refreshPermissionStates()
        }
        await requestPhotoPermissionIfNeeded()
        await synchronizeMotion(in: modelContext)
        VisitMonitoringCoordinator.shared.requestAlwaysAuthorizationIfNeeded()
        VisitMonitoringCoordinator.shared.resumeIfAuthorized()
        await synchronizeNonMotion(in: modelContext)
        MotionTransitDetectionService.shared.startLiveUpdates(
            modelContainer: JournalModelContainer.shared
        )
    }

    func synchronize(in modelContext: ModelContext) async {
        guard Self.isEnabledForCurrentProcess else { return }
        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer {
            isSynchronizing = false
            refreshPermissionStates()
        }
        await synchronizeMotion(in: modelContext)
        await synchronizeNonMotion(in: modelContext)
        VisitMonitoringCoordinator.shared.resumeIfAuthorized()
        MotionTransitDetectionService.shared.startLiveUpdates(
            modelContainer: JournalModelContainer.shared
        )
    }

    func pauseLiveUpdates() {
        MotionTransitDetectionService.shared.stopLiveUpdates()
    }

    func refreshPermissionStates() {
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        photoPermission = switch photoStatus {
        case .authorized: .allowed
        case .limited: .limited
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .unavailable
        }

        if !CMMotionActivityManager.isActivityAvailable() {
            motionPermission = .unavailable
        } else {
            motionPermission = switch CMMotionActivityManager
                .authorizationStatus() {
            case .authorized: .allowed
            case .denied, .restricted: .denied
            case .notDetermined: .notDetermined
            @unknown default: .unavailable
            }
        }

        locationPermission = switch VisitMonitoringCoordinator.shared
            .authorizationStatus {
        case .authorizedAlways: .allowed
        case .authorizedWhenInUse: .limited
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .unavailable
        }
    }

    private func requestPhotoPermissionIfNeeded() async {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite)
            == .notDetermined else { return }
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        refreshPermissionStates()
    }

    private func synchronizeMotion(in modelContext: ModelContext) async {
        do {
            try await MotionTransitDetectionService.shared.reconcile(
                in: modelContext
            )
        } catch {
            print("Motion activity synchronization failed: \(error)")
        }
    }

    private func synchronizeNonMotion(in modelContext: ModelContext) async {
        do {
            try await VisitMonitoringCoordinator.shared
                .enrichClosedVisits(in: modelContext)
        } catch {
            print("Visit enrichment failed: \(error)")
        }
        do {
            try AutomationCandidateEntryService.synchronizePending(
                in: modelContext
            )
        } catch {
            print("Candidate timeline synchronization failed: \(error)")
        }
        do {
            try await PhotoAutoLinkService.synchronize(in: modelContext)
        } catch {
            print("Automatic photo linking failed: \(error)")
        }
    }
}
