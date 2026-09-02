//
//  LocationService.swift
//  Journal
//

import CoreLocation
import Foundation
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

    private let manager = CLLocationManager()

    private init() {}

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

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

    nonisolated func location(
        at coordinate: CLLocationCoordinate2D
    ) async -> Location {
        await Self.resolvedLocation(at: coordinate)
    }

    nonisolated static func resolvedLocation(
        at coordinate: CLLocationCoordinate2D
    ) async -> Location {
        await Task.detached(priority: .utility) {
            await resolveLocation(at: coordinate)
        }.value
    }

    nonisolated private static func resolveLocation(
        at coordinate: CLLocationCoordinate2D
    ) async -> Location {
        let currentLocation = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        let metadata = await reverseGeocode(currentLocation)

        return Location(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            formattedAddress: metadata.address,
            compactAddress: metadata.compactAddress,
            timeZoneIdentifier: metadata.timeZoneIdentifier,
            cityName: metadata.cityName,
            countryName: metadata.countryName,
            countryCode: metadata.countryCode
        )
    }

    nonisolated static func compactAddress(for mapItem: MKMapItem) -> String? {
        let primary = nonempty(mapItem.name)
            ?? nonempty(mapItem.address?.shortAddress)
        let city = nonempty(mapItem.addressRepresentations?.cityName)

        guard let primary else { return city }
        guard let city,
              normalized(primary) != normalized(city),
              !normalized(primary).contains(normalized(city)) else {
            return primary
        }
        return [primary, city].joined(separator: ", ")
    }

    static func location(
        for mapItem: MKMapItem,
        fallbackName: String? = nil
    ) -> Location {
        let coordinate = mapItem.location.coordinate
        let countryName = mapItem.addressRepresentations?.regionName
        return Location(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            displayName: mapItem.name ?? fallbackName,
            systemImage: PlaceSystemImage(
                pointOfInterestCategory: mapItem.pointOfInterestCategory
            ) ?? .mappin,
            formattedAddress: mapItem.address?.fullAddress,
            compactAddress: compactAddress(for: mapItem),
            timeZoneIdentifier: mapItem.timeZone?.identifier,
            cityName: mapItem.addressRepresentations?.cityName,
            countryName: countryName,
            countryCode: countryCode(for: countryName)
        )
    }

    nonisolated private static func reverseGeocode(
        _ location: CLLocation
    ) async -> (
        address: String?,
        compactAddress: String?,
        timeZoneIdentifier: String?,
        cityName: String?,
        countryName: String?,
        countryCode: String?
    ) {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return (nil, nil, nil, nil, nil, nil)
        }

        do {
            let item = try await request.mapItems.first
            return (
                item?.address?.fullAddress,
                item.flatMap(Self.compactAddress),
                item?.timeZone?.identifier,
                item?.addressRepresentations?.cityName,
                item?.addressRepresentations?.regionName,
                Self.countryCode(
                    for: item?.addressRepresentations?.regionName
                )
            )
        } catch {
            return (nil, nil, nil, nil, nil, nil)
        }
    }

    nonisolated private static func nonempty(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    nonisolated private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }

    nonisolated private static func countryCode(
        for countryName: String?
    ) -> String? {
        guard let countryName = nonempty(countryName) else { return nil }
        return Locale.Region.isoRegions.first { region in
            guard let localized = Locale.current.localizedString(
                forRegionCode: region.identifier
            ) else { return false }
            return normalized(localized) == normalized(countryName)
        }?.identifier
    }
}
