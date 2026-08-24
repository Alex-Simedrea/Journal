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
            return try ModelContainer(
                for: LogEntry.self,
                Person.self,
                Place.self,
                TransitDetails.self,
                PlaceVisitDetails.self,
                WorkoutDetails.self,
                TransitType.self,
                AutomationCandidate.self
            )
        } catch {
            fatalError("Unable to create Journal model container: \(error)")
        }
    }()
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

        guard CLLocationManager.locationServicesEnabled() else {
            locationPermission = .unavailable
            return
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
