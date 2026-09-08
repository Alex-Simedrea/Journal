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
            let maintenance = await JournalPersistenceServices.shared.maintenance(
                for: modelContainer
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

    /// Runs on whichever executor owns the passed context; periodic
    /// synchronization calls this from `JournalBackgroundMaintenance`.
    nonisolated static func enrichClosedVisits(
        in modelContext: ModelContext,
        resolve: (Location) async throws -> Location = { location in
            await LocationService.shared.location(at: location.coordinate)
        }
    ) async throws {
        // Hold only IDs/values over geocoding. A candidate can be accepted,
        // dismissed, edited, or deleted while the lookup is suspended.
        let targets = try modelContext.fetch(FetchDescriptor<AutomationCandidate>())
            .compactMap { candidate -> (UUID, Location)? in
                guard candidate.kind == .visit, candidate.status == .pending,
                      candidate.endTime != nil,
                      let location = candidate.visitLocation else { return nil }
                return (candidate.id, location)
            }
        for (id, original) in targets {
            var resolved = original
            if original.formattedAddress == nil || original.timeZoneIdentifier == nil {
                let enriched = try await resolve(original)
                resolved = Location(
                    latitude: original.latitude, longitude: original.longitude,
                    displayName: enriched.displayName ?? original.displayName,
                    formattedAddress: enriched.formattedAddress ?? original.formattedAddress,
                    compactAddress: enriched.compactAddress ?? original.compactAddress,
                    timeZoneIdentifier: enriched.timeZoneIdentifier ?? original.timeZoneIdentifier,
                    cityName: enriched.cityName ?? original.cityName,
                    countryName: enriched.countryName ?? original.countryName,
                    countryCode: enriched.countryCode ?? original.countryCode
                )
            }
            try Task.checkCancellation()
            guard let candidate = try modelContext.fetch(FetchDescriptor<AutomationCandidate>(
                predicate: #Predicate { $0.id == id }
            )).first, candidate.status == .pending,
                  candidate.visitLocation == original else { continue }
            candidate.visitLocation = resolved
            if candidate.visitPlaceID == nil {
                let coordinate = WorkoutCoordinateSnapshot(
                    latitude: original.latitude, longitude: original.longitude,
                    horizontalAccuracyMeters: candidate.visitHorizontalAccuracyMeters ?? 0
                )
                let places = try modelContext.fetch(FetchDescriptor<Place>())
                if case .matched(let place) = WorkoutPlaceMatcher.match(
                    coordinate: coordinate, places: places
                ) {
                    candidate.visitPlaceID = place.id
                    candidate.visitLocation = place.location
                }
            }
            candidate.timeZoneIdentifier = candidate.visitLocation?
                .timeZoneIdentifier ?? candidate.timeZoneIdentifier
            candidate.updatedAt = .now
            // Never leave staged mutations across the next suspension point.
            try JournalPersistence.save(modelContext)
        }
        if modelContext.hasChanges {
            try JournalPersistence.save(modelContext)
        }
    }
}
