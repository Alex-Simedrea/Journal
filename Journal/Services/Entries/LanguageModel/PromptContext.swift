import AnyLanguageModel
import CoreLocation
import Foundation
import MapKit

struct EntryPromptContext {
    let places: [Place]
    let people: [Person]
    let transitTypes: [TransitType]
    let visitStatisticsByPlaceID: [UUID: PlaceVisitStatistics]
    let selectedDay: TimelineDayKey
    let selectedDayEntries: [LogEntry]
    let currentDate: Date
    let currentLocation: Location
}

enum EntryLocationReferenceSource: String, Hashable {
    case savedPlace
    case history
}

struct EntryLocationReference {
    let key: String
    let location: Location
    let place: Place?
    let source: EntryLocationReferenceSource
    let displayName: String
}

private struct HistoryLocationIdentity: Hashable {
    let entryID: UUID
    let role: String
}

struct EntryPromptReferences {
    let placesByKey: [String: Place]
    let peopleByKey: [String: Person]
    let locationsByKey: [String: EntryLocationReference]

    private let historyLocationKeys: [HistoryLocationIdentity: String]

    init(
        places: [Place],
        people: [Person],
        historyEntries: [LogEntry] = [],
        selectedDay: TimelineDayKey? = nil
    ) {
        placesByKey = Self.placeMap(places)
        peopleByKey = Self.personMap(people)
        var locations: [String: EntryLocationReference] = [:]
        for (key, place) in placesByKey {
            locations[key] = EntryLocationReference(
                key: key,
                location: place.location,
                place: place,
                source: .savedPlace,
                displayName: place.name
            )
        }

        var historyKeys: [HistoryLocationIdentity: String] = [:]
        for (index, entry) in historyEntries.enumerated() {
            let entryNumber = index + 1
            let dayLabel = Self.historyDayLabel(
                for: entry,
                selectedDay: selectedDay
            )
            for endpoint in Self.historyEndpoints(for: entry) {
                let identity = HistoryLocationIdentity(
                    entryID: entry.id,
                    role: endpoint.role
                )
                let key = "history-\(dayLabel)-entry-\(entryNumber)-\(endpoint.role)"
                historyKeys[identity] = key
                locations[key] = EntryLocationReference(
                    key: key,
                    location: endpoint.location,
                    place: endpoint.place,
                    source: .history,
                    displayName: endpoint.displayName
                )
            }
        }
        locationsByKey = locations
        historyLocationKeys = historyKeys
    }

    private static func historyDayLabel(
        for entry: LogEntry,
        selectedDay: TimelineDayKey?
    ) -> String {
        guard let selectedDay else { return "entry-day" }
        let anchor = entry.startTime ?? entry.endTime ?? entry.createdAt
        let timeZone = TimeZone(
            identifier: entry.startTimeZoneIdentifier
        ) ?? TimeZone(
            identifier: entry.creationTimeZoneIdentifier
        ) ?? .current
        let entryDay = TimelineDayKey(date: anchor, timeZone: timeZone)
        if entryDay == selectedDay.addingDays(-1) { return "previous-day" }
        if entryDay == selectedDay { return "selected-day" }
        if entryDay == selectedDay.addingDays(1) { return "next-day" }
        return "nearby-day"
    }

    func historyLocationKey(entryID: UUID, role: String) -> String? {
        historyLocationKeys[
            HistoryLocationIdentity(entryID: entryID, role: role)
        ]
    }

    private static func historyEndpoints(
        for entry: LogEntry
    ) -> [(role: String, location: Location, place: Place?, displayName: String)] {
        switch entry.kind {
        case .transit:
            guard let details = entry.transitDetails else { return [] }
            return [
                endpoint(
                    role: "transit-origin",
                    location: details.originLocation ?? details.originPlace?.location,
                    place: details.originPlace,
                    rawText: details.originRawText
                ),
                endpoint(
                    role: "transit-destination",
                    location: details.destinationLocation ?? details.destinationPlace?.location,
                    place: details.destinationPlace,
                    rawText: details.destinationRawText
                ),
            ].compactMap { $0 }
        case .placeVisit:
            guard let details = entry.placeVisitDetails else { return [] }
            return [
                endpoint(
                    role: "visit-location",
                    location: details.location ?? details.place?.location,
                    place: details.place,
                    rawText: details.placeRawText
                ),
            ].compactMap { $0 }
        case .workout:
            guard let details = entry.workoutDetails else { return [] }
            if details.movementKind == .moving {
                return [
                    endpoint(
                        role: "workout-origin",
                        location: details.originLocation ?? details.originPlace?.location,
                        place: details.originPlace,
                        rawText: nil
                    ),
                    endpoint(
                        role: "workout-destination",
                        location: details.destinationLocation ?? details.destinationPlace?.location,
                        place: details.destinationPlace,
                        rawText: nil
                    ),
                ].compactMap { $0 }
            }
            return [
                endpoint(
                    role: "workout-location",
                    location: details.sourceLocation ?? details.place?.location,
                    place: details.place,
                    rawText: nil
                ),
            ].compactMap { $0 }
        case .wakeUp:
            return []
        }
    }

    private static func endpoint(
        role: String,
        location: Location?,
        place: Place?,
        rawText: String?
    ) -> (role: String, location: Location, place: Place?, displayName: String)? {
        guard let location else { return nil }
        return (
            role,
            location,
            place,
            place?.name
                ?? location.preferredName
                ?? rawText
                ?? String(localized: "Unnamed location")
        )
    }

    private static func placeMap(
        _ places: [Place]
    ) -> [String: Place] {
        var byKey: [String: Place] = [:]
        var usedKeys: Set<String> = []
        let placesByID = Dictionary(
            uniqueKeysWithValues: places.map { ($0.id, $0) }
        )
        let sortKeysByID = Dictionary(
            uniqueKeysWithValues: places.map {
                ($0.id, stableSortKey(name: $0.name, id: $0.id))
            }
        )
        let sortedIDs = places.map(\.id).sorted {
            sortKeysByID[$0, default: ""]
                < sortKeysByID[$1, default: ""]
        }

        for id in sortedIDs {
            guard let place = placesByID[id] else { continue }
            let key = uniqueKey(for: place.name, usedKeys: &usedKeys)
            byKey[key] = place
        }
        return byKey
    }

    private static func personMap(
        _ people: [Person]
    ) -> [String: Person] {
        var byKey: [String: Person] = [:]
        var usedKeys: Set<String> = []
        let peopleByID = Dictionary(
            uniqueKeysWithValues: people.map { ($0.id, $0) }
        )
        let sortKeysByID = Dictionary(
            uniqueKeysWithValues: people.map {
                ($0.id, stableSortKey(name: $0.name, id: $0.id))
            }
        )
        let sortedIDs = people.map(\.id).sorted {
            sortKeysByID[$0, default: ""]
                < sortKeysByID[$1, default: ""]
        }

        for id in sortedIDs {
            guard let person = peopleByID[id] else { continue }
            let key = uniqueKey(for: person.name, usedKeys: &usedKeys)
            byKey[key] = person
        }
        return byKey
    }

    private static func stableSortKey(name: String, id: UUID) -> String {
        "\(normalizedName(name))\u{0}\(id.uuidString)"
    }

    private static func uniqueKey(
        for name: String,
        usedKeys: inout Set<String>
    ) -> String {
        let base = slug(name).isEmpty ? "item" : slug(name)
        var candidate = base
        var suffix = 2
        while !usedKeys.insert(candidate).inserted {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private static func slug(_ value: String) -> String {
        normalizedName(value)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .joined(separator: "-")
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
    }
}
