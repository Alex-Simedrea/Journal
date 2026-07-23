//
//  EntryLocationPickerModel.swift
//  Journal
//

import MapKit
import Observation

struct EntryLocationSelection: Identifiable, Hashable {
    let placeID: UUID?
    let location: Location
    let title: String
    let systemImage: PlaceSystemImage

    var id: String {
        if let placeID { return "saved-\(placeID.uuidString)" }
        return "location-\(location.latitude)-\(location.longitude)-\(title)"
    }

    init(place: Place) {
        placeID = place.id
        location = place.location.withFallbackDisplayName(place.name)
        title = place.name
        systemImage = place.systemImage
    }

    init(
        location: Location,
        title: String? = nil,
        systemImage: PlaceSystemImage = .mappin
    ) {
        placeID = nil
        self.location = location
        self.title = title ?? location.preferredName ?? String(localized: "Location")
        self.systemImage = systemImage
    }
}

@MainActor
@Observable
final class EntryLocationPickerModel {
    let search = LocationSearchService()
    var isResolving = false
    var errorMessage: String?

    func resolve(
        _ suggestion: LocationSearchSuggestion
    ) async -> EntryLocationSelection? {
        isResolving = true
        errorMessage = nil
        defer { isResolving = false }

        do {
            let mapItem = try await search.resolve(suggestion)
            let coordinate = mapItem.location.coordinate
            let location = Location(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                displayName: mapItem.name ?? suggestion.title,
                formattedAddress: mapItem.address?.fullAddress,
                compactAddress: LocationService.compactAddress(for: mapItem),
                timeZoneIdentifier: mapItem.timeZone?.identifier
            )
            return EntryLocationSelection(
                location: location,
                title: mapItem.name ?? suggestion.title
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func currentLocation() async -> EntryLocationSelection? {
        isResolving = true
        errorMessage = nil
        defer { isResolving = false }

        do {
            let location = try await LocationService.shared.captureCurrentLocation()
            return EntryLocationSelection(
                location: location,
                title: String(localized: "Current Location")
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
