import CoreLocation
import Foundation
import SwiftData

@MainActor
final class VisitMonitoringCoordinator: NSObject, CLLocationManagerDelegate {
    static let shared = VisitMonitoringCoordinator()

    private let manager = CLLocationManager()
    private var modelContainer: ModelContainer?

    private override init() {
        super.init()
        manager.delegate = self
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func requestAlwaysAuthorizationIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways, .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func resumeIfAuthorized() {
        guard manager.authorizationStatus == .authorizedAlways else { return }
        manager.startMonitoringVisits()
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        if manager.authorizationStatus == .authorizedAlways {
            manager.startMonitoringVisits()
        }
        AutomationCoordinator.shared.refreshPermissionStates()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didVisit visit: CLVisit
    ) {
        guard let modelContainer else { return }
        let departureDate = visit.departureDate == .distantFuture
            ? nil
            : visit.departureDate
        let snapshot = VisitDetectionSnapshot(
            arrivalDate: visit.arrivalDate,
            departureDate: departureDate,
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude,
            horizontalAccuracyMeters: visit.horizontalAccuracy
        )
        Task {
            let maintenance = await JournalPersistenceActors.shared.maintenance(
                for: JournalModelContainerReference(modelContainer)
            )
            await maintenance.persistVisit(snapshot)
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: any Error
    ) {
        print("Visit monitoring failed: \(error)")
    }

    nonisolated static func enrichClosedVisits(
        in modelContext: ModelContext
    ) async throws {
        let candidates = try modelContext.fetch(
            FetchDescriptor<AutomationCandidate>()
        ).filter {
            $0.kind == .visit
                && $0.endTime != nil
                && $0.visitLocation != nil
        }
        guard !candidates.isEmpty else { return }
        let places = try modelContext.fetch(FetchDescriptor<Place>())

        for candidate in candidates {
            guard let storedLocation = candidate.visitLocation else { continue }
            if storedLocation.formattedAddress == nil
                || storedLocation.timeZoneIdentifier == nil {
                let enriched = await LocationService.shared.location(
                    at: storedLocation.coordinate
                )
                candidate.visitLocation = Location(
                    latitude: storedLocation.latitude,
                    longitude: storedLocation.longitude,
                    displayName: enriched.displayName
                        ?? storedLocation.displayName,
                    formattedAddress: enriched.formattedAddress
                        ?? storedLocation.formattedAddress,
                    compactAddress: enriched.compactAddress
                        ?? storedLocation.compactAddress,
                    timeZoneIdentifier: enriched.timeZoneIdentifier
                        ?? storedLocation.timeZoneIdentifier,
                    cityName: enriched.cityName ?? storedLocation.cityName,
                    countryName: enriched.countryName
                        ?? storedLocation.countryName,
                    countryCode: enriched.countryCode
                        ?? storedLocation.countryCode
                )
            }

            if candidate.visitPlaceID == nil {
                let coordinate = WorkoutCoordinateSnapshot(
                    latitude: storedLocation.latitude,
                    longitude: storedLocation.longitude,
                    horizontalAccuracyMeters: candidate
                        .visitHorizontalAccuracyMeters ?? 0
                )
                if case .matched(let place) = WorkoutPlaceMatcher.match(
                    coordinate: coordinate,
                    places: places
                ) {
                    candidate.visitPlaceID = place.id
                    candidate.visitLocation = place.location
                }
            }
            candidate.timeZoneIdentifier = candidate.visitLocation?
                .timeZoneIdentifier ?? candidate.timeZoneIdentifier
            candidate.updatedAt = .now
        }
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}
