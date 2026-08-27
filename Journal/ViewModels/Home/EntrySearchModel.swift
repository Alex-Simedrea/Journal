import Foundation
import Observation
import SwiftData

nonisolated struct EntrySearchSection: Identifiable, Hashable, Sendable {
    let day: TimelineDayKey
    let occurrences: [TimelineOccurrence]

    var id: TimelineDayKey { day }
}

nonisolated struct EntrySearchCandidate: Hashable, Sendable {
    let occurrence: TimelineOccurrence
    let searchableTerms: [String]

    init(snapshot: TimelineEntrySnapshot) {
        occurrence = Self.occurrence(for: snapshot)
        searchableTerms = Self.searchableTerms(for: snapshot)
            .map(EntrySearchIndex.normalize)
            .filter { !$0.isEmpty }
    }

    private static func searchableTerms(
        for snapshot: TimelineEntrySnapshot
    ) -> [String] {
        var terms = snapshot.people.map(\.name)

        switch snapshot.kind {
        case .transit:
            terms.append(contentsOf: [
                snapshot.transitType,
                snapshot.origin,
                snapshot.destination,
            ])
            terms.append(contentsOf: locationTerms(snapshot.originLocation))
            terms.append(contentsOf: locationTerms(snapshot.destinationLocation))
        case .placeVisit:
            terms.append(snapshot.visitPlace)
            terms.append(contentsOf: locationTerms(snapshot.visitLocation))
        case .workout:
            terms.append(contentsOf: [
                snapshot.workoutOrigin,
                snapshot.workoutDestination,
                snapshot.workoutPlace,
            ])
            terms.append(contentsOf: locationTerms(snapshot.workoutOriginLocation))
            terms.append(contentsOf: locationTerms(snapshot.workoutDestinationLocation))
            terms.append(contentsOf: locationTerms(snapshot.workoutPlaceLocation))
        case .wakeUp:
            break
        }

        return terms
    }

    private static func locationTerms(
        _ location: TimelineLocationSnapshot?
    ) -> [String] {
        guard let location else { return [] }
        return [
            location.name,
            location.cityName,
            location.countryName,
            location.countryCode,
        ].compactMap { $0 }
    }

    private static func occurrence(
        for snapshot: TimelineEntrySnapshot
    ) -> TimelineOccurrence {
        let role: TimelineOccurrenceRole
        let day: TimelineDayKey
        let timeZone: TimeZone
        let sortTime: Date
        let visibleStartTime: Date?
        let visibleEndTime: Date?
        let endTimeZoneIdentifier: String

        if snapshot.kind == .wakeUp, let wakeTime = snapshot.endTime {
            role = .wakeUp
            timeZone = resolvedTimeZone(
                snapshot.endTimeZoneIdentifier,
                fallback: snapshot.creationTimeZoneIdentifier
            )
            day = TimelineDayKey(date: wakeTime, timeZone: timeZone)
            sortTime = wakeTime
            visibleStartTime = wakeTime
            visibleEndTime = wakeTime
            endTimeZoneIdentifier = timeZone.identifier
        } else if let startTime = snapshot.startTime,
                  let endTime = snapshot.endTime,
                  endTime > startTime {
            role = .intervalDay
            timeZone = resolvedTimeZone(
                snapshot.startTimeZoneIdentifier,
                fallback: snapshot.creationTimeZoneIdentifier
            )
            day = TimelineDayKey(date: startTime, timeZone: timeZone)
            sortTime = startTime
            visibleStartTime = startTime
            visibleEndTime = endTime
            endTimeZoneIdentifier = resolvedTimeZone(
                snapshot.endTimeZoneIdentifier,
                fallback: snapshot.creationTimeZoneIdentifier
            ).identifier
        } else {
            role = .unresolvedReview
            timeZone = resolvedTimeZone(
                snapshot.creationTimeZoneIdentifier,
                fallback: TimeZone.current.identifier
            )
            day = TimelineDayKey(date: snapshot.createdAt, timeZone: timeZone)
            sortTime = snapshot.startTime
                ?? snapshot.endTime
                ?? snapshot.createdAt
            visibleStartTime = snapshot.startTime
            visibleEndTime = snapshot.endTime
            endTimeZoneIdentifier = timeZone.identifier
        }

        return TimelineOccurrence(
            id: TimelineOccurrenceID(
                entryID: snapshot.id,
                day: day,
                timeZoneIdentifier: timeZone.identifier,
                role: role
            ),
            entryID: snapshot.id,
            role: role,
            timeZoneIdentifier: timeZone.identifier,
            endTimeZoneIdentifier: endTimeZoneIdentifier,
            sortTime: sortTime,
            visibleStartTime: visibleStartTime,
            visibleEndTime: visibleEndTime,
            startTime: snapshot.startTime,
            endTime: snapshot.endTime,
            needsReview: snapshot.needsReview,
            kind: snapshot.kind,
            snapshot: snapshot
        )
    }

    private static func resolvedTimeZone(
        _ identifier: String,
        fallback: String
    ) -> TimeZone {
        TimeZone(identifier: identifier)
            ?? TimeZone(identifier: fallback)
            ?? .current
    }
}

nonisolated enum EntrySearchIndex {
    static func sections(
        matching query: String,
        in candidates: [EntrySearchCandidate]
    ) -> [EntrySearchSection] {
        let tokens = normalize(query)
            .split(separator: " ")
            .map(String.init)
        guard !tokens.isEmpty else { return [] }

        let matches = candidates.filter { candidate in
            tokens.allSatisfy { token in
                candidate.searchableTerms.contains { $0.contains(token) }
            }
        }
        let grouped = Dictionary(grouping: matches) {
            $0.occurrence.id.day
        }

        return grouped.keys.sorted(by: >).map { day in
            let occurrences = grouped[day, default: []]
                .map(\.occurrence)
                .sorted(by: occurrenceOrder)
            return EntrySearchSection(day: day, occurrences: occurrences)
        }
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .components(
                separatedBy: CharacterSet.alphanumerics.inverted
            )
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func occurrenceOrder(
        _ lhs: TimelineOccurrence,
        _ rhs: TimelineOccurrence
    ) -> Bool {
        if lhs.sortTime != rhs.sortTime {
            return lhs.sortTime < rhs.sortTime
        }
        return lhs.entryID.uuidString < rhs.entryID.uuidString
    }
}

@MainActor
@Observable
final class EntrySearchModel {
    var query = ""
    private(set) var sections: [EntrySearchSection] = []
    private(set) var errorMessage: String?

    @ObservationIgnored
    private var entriesByID: [UUID: LogEntry] = [:]
    @ObservationIgnored
    private var candidates: [EntrySearchCandidate] = []

    var hasQuery: Bool {
        !EntrySearchIndex.normalize(query).isEmpty
    }

    func load(in modelContext: ModelContext) {
        do {
            let entries = try modelContext.fetch(
                FetchDescriptor<LogEntry>(
                    sortBy: [SortDescriptor(\LogEntry.createdAt)]
                )
            )
            entriesByID = Dictionary(
                uniqueKeysWithValues: entries.map { ($0.id, $0) }
            )
            candidates = entries.map {
                EntrySearchCandidate(snapshot: TimelineEntrySnapshot(entry: $0))
            }
            errorMessage = nil
            applySearch()
        } catch {
            entriesByID = [:]
            candidates = []
            sections = []
            errorMessage = error.localizedDescription
        }
    }

    func entry(withID id: UUID) -> LogEntry? {
        entriesByID[id]
    }

    func queryDidChange() {
        applySearch()
    }

    func submitSearch() {
        applySearch()
    }

    private func applySearch() {
        sections = EntrySearchIndex.sections(
            matching: query,
            in: candidates
        )
    }
}
