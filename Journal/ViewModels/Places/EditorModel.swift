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
    private(set) var location: Location?
    var accuracyRadiusMeters: Double
    var mapPosition: MapCameraPosition
    var isLoadingLocation: Bool
    var isResolvingSearch = false
    var locationErrorMessage: String?
    var searchErrorMessage: String?
    var saveErrorMessage: String?

    @ObservationIgnored
    let locationSearch = LocationSearchService()

    @ObservationIgnored
    private var locationUpdateTask: Task<Void, Never>?

    @ObservationIgnored
    private var currentLocationRequestID: UUID?

    @ObservationIgnored
    private var mapPresentationID: UUID?

    @ObservationIgnored
    private let currentLocationProvider: () async throws -> Location

    @ObservationIgnored
    private let coordinateLocationProvider:
        (CLLocationCoordinate2D) async -> Location

    init(
        place: Place? = nil,
        initialName: String = "",
        initialSearchQuery: String = "",
        initialLocation: Location? = nil,
        initialSymbol: PlaceSystemImage = .mappin,
        allowsCurrentLocationCapture: Bool = true,
        currentLocationProvider: @escaping () async throws -> Location = {
            try await LocationService.shared.captureCurrentLocation()
        },
        coordinateLocationProvider: @escaping (CLLocationCoordinate2D) async
            -> Location = {
            await LocationService.shared.location(at: $0)
        }
    ) {
        self.allowsCurrentLocationCapture = allowsCurrentLocationCapture
        self.currentLocationProvider = currentLocationProvider
        self.coordinateLocationProvider = coordinateLocationProvider
        let initialResolvedLocation = place?.location ?? initialLocation
        name = place?.name ?? initialName
        selectedSymbol = place?.systemImage ?? initialSymbol
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
        locationUpdateTask?.cancel()
        let requestID = UUID()
        currentLocationRequestID = requestID
        isLoadingLocation = true
        locationErrorMessage = nil

        defer {
            if currentLocationRequestID == requestID {
                currentLocationRequestID = nil
                isLoadingLocation = false
            }
        }

        do {
            let capturedLocation = try await currentLocationProvider()
            guard currentLocationRequestID == requestID,
                  !Task.isCancelled else { return }
            location = capturedLocation
            mapPosition = .region(
                region(center: capturedLocation.coordinate, meters: 100)
            )
            locationSearch.updateRegion(
                region(center: capturedLocation.coordinate, meters: 10_000)
            )
        } catch {
            guard currentLocationRequestID == requestID,
                  !Task.isCancelled else { return }
            locationErrorMessage = error.localizedDescription
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
        locationSearch.updateRegion(region)
        guard positionedByUser, let mapPresentationID else { return }
        invalidateCurrentLocationCapture()
        updateLocation(to: coordinate, mapPresentationID: mapPresentationID)
    }

    func mapDidAppear() {
        locationUpdateTask?.cancel()
        mapPresentationID = UUID()
        guard let location else { return }
        mapPosition = .region(
            region(center: location.coordinate, meters: 200)
        )
        locationSearch.updateRegion(
            region(center: location.coordinate, meters: 10_000)
        )
    }

    func mapDidDisappear() {
        mapPresentationID = nil
        locationUpdateTask?.cancel()
        locationUpdateTask = nil
    }

    func selectSearchSuggestion(_ suggestion: LocationSearchSuggestion) {
        invalidateCurrentLocationCapture()
        locationUpdateTask?.cancel()
        searchErrorMessage = nil
        isResolvingSearch = true

        locationUpdateTask = Task {
            defer { isResolvingSearch = false }

            do {
                let mapItem = try await locationSearch.resolve(suggestion)
                let coordinate = mapItem.location.coordinate
                let inferredSymbol = PlaceSystemImage(
                    pointOfInterestCategory: mapItem.pointOfInterestCategory
                )

                guard !Task.isCancelled else { return }

                setUserSelectedLocation(
                    Location(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude,
                        displayName: suggestion.title,
                        systemImage: inferredSymbol ?? .mappin,
                        formattedAddress: mapItem.address?.fullAddress,
                        compactAddress: LocationService.compactAddress(
                            for: mapItem
                        ),
                        timeZoneIdentifier: mapItem.timeZone?.identifier
                    ),
                    mapMeters: 500
                )

                if trimmedName.isEmpty {
                    name = suggestion.title
                }

                if let inferredSymbol {
                    selectedSymbol = inferredSymbol
                }

                locationSearch.clear()
            } catch {
                guard !Task.isCancelled else { return }
                searchErrorMessage = error.localizedDescription
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
        invalidateCurrentLocationCapture()
        mapDidDisappear()
    }

    func setUserSelectedLocation(
        _ location: Location,
        mapMeters: CLLocationDistance? = nil
    ) {
        invalidateCurrentLocationCapture()
        self.location = location
        locationErrorMessage = nil
        if let mapMeters {
            mapPosition = .region(
                region(center: location.coordinate, meters: mapMeters)
            )
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateLocation(
        to coordinate: CLLocationCoordinate2D,
        mapPresentationID: UUID
    ) {
        locationUpdateTask?.cancel()
        locationUpdateTask = Task {
            let updatedLocation = await coordinateLocationProvider(coordinate)

            guard !Task.isCancelled,
                  self.mapPresentationID == mapPresentationID else { return }
            setUserSelectedLocation(updatedLocation)
        }
    }

    private func invalidateCurrentLocationCapture() {
        currentLocationRequestID = nil
        isLoadingLocation = false
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
