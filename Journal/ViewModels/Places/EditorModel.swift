//
//  PlaceEditorModel.swift
//  Journal
//

import CoreLocation
import MapKit
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class PlaceEditorModel {
    let allowsCurrentLocationCapture: Bool
    var name: String
    var selectedSymbol: PlaceSystemImage
    var location: Location?
    var accuracyRadiusMeters: Double
    var mapPosition: MapCameraPosition
    var isLoadingLocation: Bool
    var isResolvingSearch = false
    var isSuggestingSymbol = false
    var locationErrorMessage: String?
    var searchErrorMessage: String?
    var saveErrorMessage: String?

    @ObservationIgnored
    let locationSearch = LocationSearchService()

    @ObservationIgnored
    private var locationUpdateTask: Task<Void, Never>?

    @ObservationIgnored
    private var symbolSuggestionTask: Task<Void, Never>?

    init(
        place: Place? = nil,
        initialName: String = "",
        initialSearchQuery: String = "",
        initialLocation: Location? = nil,
        allowsCurrentLocationCapture: Bool = true
    ) {
        self.allowsCurrentLocationCapture = allowsCurrentLocationCapture
        let initialResolvedLocation = place?.location ?? initialLocation
        name = place?.name ?? initialName
        selectedSymbol = place?.systemImage ?? .mappin
        location = initialResolvedLocation
        accuracyRadiusMeters = place?.accuracyRadiusMeters ?? 0
        isLoadingLocation = place == nil
            && initialLocation == nil
            && allowsCurrentLocationCapture

        if let coordinate = initialResolvedLocation?.coordinate {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 200,
                    longitudinalMeters: 200
                )
            )
            locationSearch.updateRegion(
                MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 10_000,
                    longitudinalMeters: 10_000
                )
            )
        } else {
            mapPosition = .automatic
        }

        if place == nil && !initialSearchQuery.isEmpty {
            locationSearch.query = initialSearchQuery
        }
    }

    var canSave: Bool {
        !trimmedName.isEmpty && location != nil
    }

    func captureCurrentLocation() async {
        guard allowsCurrentLocationCapture else { return }
        isLoadingLocation = true
        locationErrorMessage = nil

        do {
            let capturedLocation = try await LocationService.shared
                .captureCurrentLocation()
            location = capturedLocation
            mapPosition = .region(
                region(center: capturedLocation.coordinate, meters: 100)
            )
            locationSearch.updateRegion(
                region(center: capturedLocation.coordinate, meters: 10_000)
            )
        } catch {
            location = nil
            locationErrorMessage = error.localizedDescription
        }

        isLoadingLocation = false
    }

    func mapCameraChanged(_ context: MapCameraUpdateContext) {
        locationSearch.updateRegion(context.region)
        updateLocation(to: context.camera.centerCoordinate)
    }

    func selectSearchSuggestion(_ suggestion: LocationSearchSuggestion) {
        locationUpdateTask?.cancel()
        searchErrorMessage = nil
        isResolvingSearch = true

        locationUpdateTask = Task {
            defer { isResolvingSearch = false }

            do {
                let mapItem = try await locationSearch.resolve(suggestion)
                let coordinate = mapItem.location.coordinate

                guard !Task.isCancelled else { return }

                location = Location(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    formattedAddress: mapItem.address?.fullAddress,
                    compactAddress: LocationService.compactAddress(
                        for: mapItem
                    ),
                    timeZoneIdentifier: mapItem.timeZone?.identifier
                )
                mapPosition = .region(region(center: coordinate, meters: 500))

                if trimmedName.isEmpty {
                    name = mapItem.name ?? suggestion.title
                }

                locationSearch.clear()
            } catch {
                guard !Task.isCancelled else { return }
                searchErrorMessage = error.localizedDescription
            }
        }
    }

    func nameSubmitted() {
        let submittedName = trimmedName
        guard !submittedName.isEmpty else { return }

        symbolSuggestionTask?.cancel()
        let previousSymbol = selectedSymbol
        isSuggestingSymbol = true

        symbolSuggestionTask = Task {
            defer { isSuggestingSymbol = false }

            do {
                guard let suggestion = try await PlaceIconSuggestionService
                    .suggestIcon(for: submittedName) else {
                    return
                }

                guard !Task.isCancelled else { return }
                guard trimmedName == submittedName else { return }
                guard selectedSymbol == previousSymbol else { return }

                selectedSymbol = suggestion
            } catch {
                // Icon suggestion is an enhancement. Keep the current selection
                // when the configured model can't complete the request.
            }
        }
    }

    func insertPlace(in modelContext: ModelContext) -> Place? {
        guard let location, canSave else { return nil }

        let place = Place(
            name: trimmedName,
            location: location,
            systemImage: selectedSymbol,
            accuracyRadiusMeters: accuracyRadiusMeters
        )
        modelContext.insert(place)

        do {
            try modelContext.save()
            return place
        } catch {
            modelContext.delete(place)
            saveErrorMessage = error.localizedDescription
            return nil
        }
    }

    func update(_ place: Place, in modelContext: ModelContext) -> Bool {
        guard let location, canSave else { return false }

        let previousName = place.name
        let previousSymbol = place.systemImage
        let previousLocation = place.location
        let previousAccuracyRadiusMeters = place.accuracyRadiusMeters

        place.name = trimmedName
        place.systemImage = selectedSymbol
        place.location = location
        place.accuracyRadiusMeters = accuracyRadiusMeters

        do {
            try modelContext.save()
            return true
        } catch {
            place.name = previousName
            place.systemImage = previousSymbol
            place.location = previousLocation
            place.accuracyRadiusMeters = previousAccuracyRadiusMeters
            saveErrorMessage = error.localizedDescription
            return false
        }
    }

    func stop() {
        locationUpdateTask?.cancel()
        symbolSuggestionTask?.cancel()
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateLocation(to coordinate: CLLocationCoordinate2D) {
        locationUpdateTask?.cancel()
        locationUpdateTask = Task {
            let updatedLocation = await LocationService.shared.location(
                at: coordinate
            )

            guard !Task.isCancelled else { return }
            location = updatedLocation
        }
    }

    private func region(
        center: CLLocationCoordinate2D,
        meters: CLLocationDistance
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            latitudinalMeters: meters,
            longitudinalMeters: meters
        )
    }
}
