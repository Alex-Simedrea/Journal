#if DEBUG
import SwiftData
import SwiftUI

private enum EntryDetailPreviewState: String {
    case placeWithPeople
    case movingWorkout
    case transitWithPeople
    case transitWithoutPeople
    case placeWithoutPeople
    case train
}

@MainActor
private struct EntryDetailPreviewHost: View {
    let container: ModelContainer
    let entry: LogEntry

    init(_ state: EntryDetailPreviewState) {
        let schema = Schema([
            LogEntry.self,
            Person.self,
            Place.self,
            TransitDetails.self,
            PlaceVisitDetails.self,
            WorkoutDetails.self,
            TransitType.self,
        ])
        container = try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        entry = EntryDetailPreviewFactory.entry(for: state)
        container.mainContext.insert(entry)
        try! container.mainContext.save()
    }

    var body: some View {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                EntryDetailSheet(entry: entry)
            }
            .modelContainer(container)
    }
}

@MainActor
private enum EntryDetailPreviewFactory {
    static func entry(for state: EntryDetailPreviewState) -> LogEntry {
        switch state {
        case .placeWithPeople:
            placeEntry(hasPeople: true)
        case .movingWorkout:
            workoutEntry()
        case .transitWithPeople:
            transitEntry(type: "Bolt", hasPeople: true)
        case .transitWithoutPeople:
            transitEntry(type: "Bolt", hasPeople: false)
        case .placeWithoutPeople:
            placeEntry(hasPeople: false)
        case .train:
            transitEntry(type: "Train", hasPeople: true)
        }
    }

    private static func baseEntry(kind: LogKind) -> LogEntry {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(
            from: DateComponents(
                timeZone: TimeZone(identifier: "Europe/Bucharest"),
                year: 2026,
                month: 7,
                day: 12,
                hour: 17,
                minute: 3
            )
        )!
        let entry = LogEntry(
            kind: kind,
            startTime: start,
            endTime: start.addingTimeInterval(17 * 60),
            startTimeZoneIdentifier: "Europe/Bucharest",
            endTimeZoneIdentifier: "Europe/Bucharest",
            timeConfidence: .explicit,
            photoReferences: [
                PhotoReference(assetLocalIdentifier: "preview-photo-one"),
                PhotoReference(assetLocalIdentifier: "preview-photo-two"),
            ],
            weather: EntryWeather(
                condition: "clear",
                symbolName: "sun.max.fill",
                temperatureCelsius: 31,
                humidity: 0.70,
                date: start
            ),
            endWeather: EntryWeather(
                condition: "mostlyClear",
                symbolName: "sun.horizon.fill",
                temperatureCelsius: 28,
                humidity: 0.70,
                date: start.addingTimeInterval(17 * 60)
            ),
            needsReview: false
        )
        return entry
    }

    private static func placeEntry(hasPeople: Bool) -> LogEntry {
        let place = Place(
            name: "Reyna Beach",
            location: Location(
                latitude: 45.646,
                longitude: 25.605,
                displayName: "Reyna Beach",
                timeZoneIdentifier: "Europe/Bucharest"
            ),
            systemImage: .beach
        )
        let entry = baseEntry(kind: .placeVisit)
        entry.placeVisitDetails = PlaceVisitDetails(place: place)
        if hasPeople { entry.people = previewPeople }
        return entry
    }

    private static func transitEntry(
        type: String,
        hasPeople: Bool
    ) -> LogEntry {
        let origin = Place(
            name: "Home",
            location: Location(latitude: 45.650, longitude: 25.595),
            systemImage: .house
        )
        let destination = Place(
            name: "Reyna Beach",
            location: Location(latitude: 45.638, longitude: 25.625),
            systemImage: .beach
        )
        let entry = baseEntry(kind: .transit)
        entry.transitDetails = TransitDetails(
            type: type,
            sourceOrganizationName: type == "Train" ? "CFR Călători" : nil,
            sourceServiceIdentifier: type == "Train" ? "IC536" : nil,
            originPlace: origin,
            destinationPlace: destination,
            durationSource: .manualOverride,
            distanceMeters: 5_300
        )
        if hasPeople { entry.people = previewPeople }
        return entry
    }

    private static func workoutEntry() -> LogEntry {
        let origin = Location(latitude: 45.650, longitude: 25.595)
        let destination = Location(latitude: 45.638, longitude: 25.625)
        let entry = baseEntry(kind: .workout)
        entry.workoutDetails = WorkoutDetails(
            healthKitWorkoutUUID: UUID(),
            activityTypeRawValue: 37,
            activityName: "Walk",
            movementKind: .moving,
            distanceMeters: 5_300,
            activeEnergyKilocalories: 103,
            routeImportState: .available,
            originLocation: origin,
            destinationLocation: destination,
            originPlace: Place(
                name: "Home",
                location: origin,
                systemImage: .house
            ),
            destinationPlace: Place(
                name: "Reyna Beach",
                location: destination,
                systemImage: .beach
            )
        )
        entry.people = previewPeople
        return entry
    }

    private static var previewPeople: [Person] {
        [Person(name: "Emma"), Person(name: "David"), Person(name: "Steven")]
    }
}

#Preview("Place · People") {
    EntryDetailPreviewHost(.placeWithPeople)
}

#Preview("Workout") {
    EntryDetailPreviewHost(.movingWorkout)
}

#Preview("Transit · People") {
    EntryDetailPreviewHost(.transitWithPeople)
}

#Preview("Transit · Empty People") {
    EntryDetailPreviewHost(.transitWithoutPeople)
}

#Preview("Place · Empty People") {
    EntryDetailPreviewHost(.placeWithoutPeople)
}

#Preview("Train") {
    EntryDetailPreviewHost(.train)
}
#endif
