import MapKit
import Testing

@testable import Journal

@Suite("Entry detail location editing")
struct DetailLocationEditorTests {
    @Test("Transit entries edit origin and destination")
    func transitLocationRoles() {
        #expect(
            EntryDetailLocationRouting.roles(
                for: .transit,
                workoutMovementKind: nil
            ) == [.origin, .destination]
        )
        #expect(
            EntryDetailLocationRouting.editRoute(
                for: .transit,
                workoutMovementKind: nil
            ) == .locations
        )
    }

    @Test("Static entries edit one place while moving workouts edit endpoints")
    func rolesByEntryKind() {
        #expect(
            EntryDetailLocationRouting.roles(
                for: .placeVisit,
                workoutMovementKind: nil
            ) == [.place]
        )
        #expect(
            EntryDetailLocationRouting.roles(
                for: .workout,
                workoutMovementKind: .staticWorkout
            ) == [.place]
        )
        #expect(
            EntryDetailLocationRouting.roles(
                for: .workout,
                workoutMovementKind: .moving
            ) == [.origin, .destination]
        )
    }

    @Test("Saved place search matches names and addresses")
    @MainActor
    func savedPlaceSearch() {
        let office = Place(
            name: "Studio",
            location: Location(
                latitude: 44.43,
                longitude: 26.10,
                compactAddress: "Piața Romană, București"
            )
        )
        let station = Place(
            name: "Gara de Nord",
            location: Location(
                latitude: 44.45,
                longitude: 26.08,
                compactAddress: "Bucharest"
            )
        )

        #expect(
            EntryLocationPickerProjection.filteredPlaces(
                [office, station],
                query: "piata"
            ).map(\.id) == [office.id]
        )
        #expect(
            EntryLocationPickerProjection.filteredPlaces(
                [office, station],
                query: "bucharest"
            ).map(\.id) == [station.id]
        )
    }

    @Test("Selecting a saved place exits search and retains its identity")
    @MainActor
    func savedPlaceSelection() {
        let place = Place(
            name: "Studio",
            location: Location(latitude: 44.43, longitude: 26.10)
        )
        let model = EntryLocationPickerModel()
        model.searchText = "Studio"

        model.select(place)

        #expect(model.searchText.isEmpty)
        #expect(model.selection?.placeID == place.id)
        #expect(model.selection?.title == "Studio")
    }

    @Test("Programmatic map movement retains a saved-place association")
    @MainActor
    func programmaticMapMovement() {
        let place = Place(
            name: "Home",
            location: Location(latitude: 44.43, longitude: 26.10)
        )
        let model = EntryLocationPickerModel()
        model.prepare(selection: EntryLocationSelection(place: place))
        let coordinate = CLLocationCoordinate2D(
            latitude: 44.431,
            longitude: 26.101
        )

        model.mapCameraChanged(
            to: coordinate,
            region: MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 700,
                longitudinalMeters: 700
            ),
            positionedByUser: false
        )

        #expect(model.selection?.placeID == place.id)
        #expect(model.selection?.title == "Home")
    }
}
