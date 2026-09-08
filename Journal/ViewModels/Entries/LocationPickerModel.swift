//
//  EntryLocationPickerModel.swift
//  Journal
//

import MapKit
import Observation
import SwiftUI

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
        systemImage: PlaceSystemImage? = nil
    ) {
        placeID = nil
        self.location = location
        self.title = title ?? location.preferredName ?? String(localized: "Location")
        self.systemImage = systemImage ?? location.systemImage ?? .mappin
    }
}

@MainActor
@Observable
final class EntryLocationPickerModel {
    let search = LocationSearchService()
    var searchText = "" {
        didSet {
            if search.query != searchText {
                search.query = searchText
            }
        }
    }
    var selection: EntryLocationSelection?
    var mapPosition: MapCameraPosition = .automatic
    var isResolving = false
    var errorMessage: String?

    @ObservationIgnored
    private var mapUpdateTask: Task<Void, Never>?
    @ObservationIgnored private var selectionRevision = 0
    @ObservationIgnored private var onSelectionChange: ((EntryLocationSelection) -> Void)?
    @ObservationIgnored private let currentLocationProvider: () async throws -> Location

    init(currentLocationProvider: @escaping () async throws -> Location = {
        try await LocationService.shared.captureCurrentLocation()
    }) {
        self.currentLocationProvider = currentLocationProvider
    }

    func prepare(
        selection: EntryLocationSelection?,
        onSelectionChange: ((EntryLocationSelection) -> Void)? = nil
    ) {
        stop()
        self.onSelectionChange = onSelectionChange
        isResolving = false
        errorMessage = nil
        searchText = ""
        search.clear()
        self.selection = selection

        guard let selection else {
            mapPosition = .automatic
            return
        }
        moveMap(to: selection.location.coordinate, meters: 700)
    }

    func select(_ place: Place) {
        searchText = ""
        search.clear()
        setSelection(EntryLocationSelection(place: place))
    }

    @discardableResult
    func resolve(_ suggestion: LocationSearchSuggestion) async -> EntryLocationSelection? {
        let revision = beginResolution()
        errorMessage = nil
        defer { if revision == selectionRevision { isResolving = false } }

        do {
            let mapItem = try await search.resolve(suggestion)
            guard revision == selectionRevision, !Task.isCancelled else { return nil }
            var location = LocationService.location(
                for: mapItem,
                fallbackName: suggestion.title
            )
            location.displayName = suggestion.title
            let resolved = EntryLocationSelection(location: location, title: suggestion.title)
            setSelection(resolved)
            searchText = ""
            search.clear()
            return resolved
        } catch {
            guard revision == selectionRevision, !Task.isCancelled else { return nil }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func useCurrentLocation() async -> EntryLocationSelection? {
        let revision = beginResolution()
        errorMessage = nil
        defer { if revision == selectionRevision { isResolving = false } }

        do {
            let location = try await currentLocationProvider()
            guard revision == selectionRevision, !Task.isCancelled else { return nil }
            let resolved = EntryLocationSelection(
                location: location, title: String(localized: "Current Location")
            )
            setSelection(resolved)
            return resolved
        } catch {
            guard revision == selectionRevision, !Task.isCancelled else { return nil }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func mapCameraChanged(_ context: MapCameraUpdateContext) {
        mapCameraChanged(
            to: context.camera.centerCoordinate,
            region: context.region,
            positionedByUser: mapPosition.positionedByUser
        )
    }

    func mapCameraChanged(
        to coordinate: CLLocationCoordinate2D,
        region: MKCoordinateRegion,
        positionedByUser: Bool
    ) {
        search.updateRegion(region)
        guard positionedByUser else { return }
        let revision = beginResolution()
        mapUpdateTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let location = await LocationService.shared.location(at: coordinate)
            guard !Task.isCancelled, revision == selectionRevision else { return }
            let selection = EntryLocationSelection(location: location)
            self.selection = selection
            onSelectionChange?(selection)
            isResolving = false
        }
    }

    func stop() {
        selectionRevision &+= 1
        mapUpdateTask?.cancel()
        onSelectionChange = nil
        isResolving = false
    }

    private func beginResolution() -> Int {
        selectionRevision &+= 1
        mapUpdateTask?.cancel()
        isResolving = true
        return selectionRevision
    }

    private func setSelection(_ selection: EntryLocationSelection) {
        selectionRevision &+= 1
        mapUpdateTask?.cancel()
        isResolving = false
        self.selection = selection
        onSelectionChange?(selection)
        moveMap(to: selection.location.coordinate, meters: 700)
    }

    private func moveMap(
        to coordinate: CLLocationCoordinate2D,
        meters: CLLocationDistance
    ) {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: meters,
            longitudinalMeters: meters
        )
        mapPosition = .region(region)
        search.updateRegion(region)
    }
}

enum EntryLocationSearchResult: Identifiable {
    case savedPlace(Place)
    case mapKit(LocationSearchSuggestion)

    var id: String {
        switch self {
        case .savedPlace(let place):
            "saved-\(place.id.uuidString)"
        case .mapKit(let suggestion):
            "map-\(suggestion.id)"
        }
    }
}

enum EntryLocationPickerProjection {
    static func filteredPlaces(
        _ places: [Place],
        query: String
    ) -> [Place] {
        let query = normalized(query)
        guard !query.isEmpty else { return places }
        return places.filter { place in
            normalized(
                [
                    place.name,
                    place.location.compactAddress,
                    place.location.formattedAddress,
                ]
                .compactMap { $0 }
                .joined(separator: " ")
            ).contains(query)
        }
    }

    static func interleavedSearchResults(
        places: [Place],
        suggestions: [LocationSearchSuggestion]
    ) -> [EntryLocationSearchResult] {
        var results: [EntryLocationSearchResult] = []
        results.reserveCapacity(places.count + suggestions.count)
        for index in 0..<max(places.count, suggestions.count) {
            if places.indices.contains(index) {
                results.append(.savedPlace(places[index]))
            }
            if suggestions.indices.contains(index) {
                results.append(.mapKit(suggestions[index]))
            }
        }
        return results
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
