import Foundation
import SwiftData
import Testing

@testable import Journal

@Suite("Entry weather")
@MainActor
struct EntryWeatherTests {
    @Test("Transit weather uses the start time and origin")
    func transitRequestUsesOrigin() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let origin = Place(
            name: "Origin",
            location: Location(latitude: 45.65, longitude: 25.60)
        )
        let destination = Place(
            name: "Destination",
            location: Location(latitude: 40.71, longitude: -74.01)
        )
        let entry = LogEntry(
            kind: .transit,
            startTime: start,
            needsReview: false
        )
        entry.transitDetails = TransitDetails(
            type: "Flight",
            originPlace: origin,
            destinationPlace: destination
        )

        let request = try #require(EntryWeatherService.request(for: entry))
        #expect(request.date == start)
        #expect(request.latitude == origin.location.latitude)
        #expect(request.longitude == origin.location.longitude)
    }

    @Test("Visit weather uses the associated place")
    func visitRequestUsesPlace() throws {
        let place = Place(
            name: "Cafe",
            location: Location(latitude: 45.64, longitude: 25.59)
        )
        let entry = LogEntry(
            kind: .placeVisit,
            startTime: Date(timeIntervalSince1970: 2_000),
            needsReview: false
        )
        entry.placeVisitDetails = PlaceVisitDetails(place: place)

        let request = try #require(EntryWeatherService.request(for: entry))
        #expect(request.latitude == place.location.latitude)
        #expect(request.longitude == place.location.longitude)
    }

    @Test("Unresolved entries do not guess a weather location")
    func unresolvedEntryHasNoRequest() {
        let entry = LogEntry(
            kind: .transit,
            startTime: .now,
            needsReview: true
        )
        entry.transitDetails = TransitDetails(
            type: "Walk",
            originRawText: "somewhere"
        )

        #expect(EntryWeatherService.request(for: entry) == nil)
    }

    @Test("Weather snapshots persist on entries")
    func snapshotPersists() throws {
        let schema = Schema([
            LogEntry.self,
            Person.self,
            Place.self,
            TransitDetails.self,
            PlaceVisitDetails.self,
            WorkoutDetails.self,
            TransitType.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let date = Date(timeIntervalSince1970: 3_000)
        let entry = LogEntry(kind: .placeVisit, needsReview: false)
        entry.weather = EntryWeather(
            condition: "clear",
            symbolName: "sun.max.fill",
            temperatureCelsius: 24.5,
            humidity: 0.63,
            date: date
        )
        context.insert(entry)
        try context.save()

        let fetched = try #require(
            context.fetch(FetchDescriptor<LogEntry>()).first
        )
        #expect(fetched.weather?.condition == "clear")
        #expect(fetched.weather?.temperatureCelsius == 24.5)
        #expect(fetched.weather?.humidity == 0.63)
        #expect(fetched.weather?.date == date)
    }
}
