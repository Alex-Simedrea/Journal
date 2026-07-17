//
//  LocationService.swift
//  Journal
//

import CoreLocation
import MapKit

enum LocationCaptureError: LocalizedError {
    case authorizationDenied
    case locationUnavailable
    case approximateLocation
    case invalidCoordinate

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Location access was denied. You can enable it in Settings."
        case .locationUnavailable:
            "Your current location could not be determined."
        case .approximateLocation:
            "Precise Location is disabled for this app."
        case .invalidCoordinate:
            "The device returned an invalid coordinate."
        }
    }
}

@MainActor
final class LocationService {
    static let shared = LocationService()

    private init() {}

    func captureCurrentLocation() async throws -> Location {
        for try await update in CLLocationUpdate.liveUpdates() {
            if update.authorizationDenied {
                throw LocationCaptureError.authorizationDenied
            }

            if update.accuracyLimited {
                throw LocationCaptureError.approximateLocation
            }

            guard let currentLocation = update.location else {
                if update.locationUnavailable {
                    throw LocationCaptureError.locationUnavailable
                }

                continue
            }

            guard CLLocationCoordinate2DIsValid(currentLocation.coordinate) else {
                throw LocationCaptureError.invalidCoordinate
            }

            guard currentLocation.horizontalAccuracy >= 0 else { continue }
            guard abs(currentLocation.timestamp.timeIntervalSinceNow) < 30 else {
                continue
            }

            return await location(at: currentLocation.coordinate)
        }

        throw LocationCaptureError.locationUnavailable
    }

    func location(at coordinate: CLLocationCoordinate2D) async -> Location {
        let currentLocation = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        let metadata = await reverseGeocode(currentLocation)

        return Location(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            formattedAddress: metadata.address,
            timeZoneIdentifier: metadata.timeZoneIdentifier
        )
    }

    private func reverseGeocode(
        _ location: CLLocation
    ) async -> (address: String?, timeZoneIdentifier: String?) {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return (nil, nil)
        }

        do {
            let item = try await request.mapItems.first
            return (
                item?.address?.fullAddress,
                item?.timeZone?.identifier
            )
        } catch {
            return (nil, nil)
        }
    }
}
