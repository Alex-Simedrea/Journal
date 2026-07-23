import AnyLanguageModel
import CoreLocation
import Foundation
import MapKit

extension EntryLanguageModelService {
    static func prompt(
        input: String,
        context: EntryPromptContext,
        references: EntryPromptReferences
    ) -> String {
        let currentTimeZone = TimeZone(
            identifier: context.currentLocation.timeZoneIdentifier
                ?? TimeZone.current.identifier
        ) ?? .current
        let selectedDayIsToday = TimelineDayKey(
            date: context.currentDate,
            timeZone: currentTimeZone
        ) == context.selectedDay
        let entryDateContext: EntryDatePromptContext = if selectedDayIsToday {
            .today(
                timestampISO8601: iso8601String(
                    context.currentDate,
                    in: currentTimeZone
                ),
                timeZoneIdentifier: currentTimeZone.identifier
            )
        } else {
            .selectedDate(
                localDate: localDateString(context.selectedDay),
                timeZoneIdentifier: currentTimeZone.identifier
            )
        }
        let payload = EntryPromptPayload(
            currentLocationContext: EntryCurrentLocationContext(
                currentAddress: context.currentLocation.formattedAddress
            ),
            selectedDayHistory: selectedDayHistoryContext(
                context: context,
                references: references
            ),
            savedPlaces: savedPlaceContext(
                context: context,
                references: references
            ),
            people: peopleContext(references),
            transitTypes: context.transitTypes
                .sorted { $0.canonicalName < $1.canonicalName }
                .map {
                    TransitTypePromptContext(
                        canonicalName: $0.canonicalName,
                        aliases: $0.aliases,
                        routingMode: $0.routingMode.rawValue
                    )
                },
            userEntryText: input
        )

        return """
        ENTRY DATE CONTEXT — AUTHORITATIVE FOR THE NEW ENTRY:
        \(encoded(entryDateContext))

        Classify and resolve one journal entry from the remaining JSON context. Interpret the
        user's prompt as occurring on the entry date above, not automatically on the device's
        real-world current date:
        \(encoded(payload))
        """
    }

    static func iso8601String(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withColonSeparatorInTimeZone,
        ]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    static func localDateString(_ day: TimelineDayKey) -> String {
        String(
            format: "%04d-%02d-%02d",
            day.year,
            day.month,
            day.day
        )
    }

    static func savedPlaceContext(
        context: EntryPromptContext,
        references: EntryPromptReferences
    ) -> [SavedPlacePromptContext] {
        let currentLocation = CLLocation(
            latitude: context.currentLocation.latitude,
            longitude: context.currentLocation.longitude
        )

        return references.placesByKey.map { key, place in
            let placeLocation = CLLocation(
                latitude: place.location.latitude,
                longitude: place.location.longitude
            )
            let distanceKilometers = currentLocation.distance(from: placeLocation) / 1_000
            let effectiveProximityRadiusKilometers = max(
                0.2,
                place.accuracyRadiusMeters / 1_000
            )
            let statistics = context.visitStatisticsByPlaceID[place.id]
            return SavedPlacePromptContext(
                locationKey: key,
                name: place.name,
                aliases: place.aliases,
                address: place.location.formattedAddress,
                timeZoneIdentifier: place.location.timeZoneIdentifier,
                distanceFromCurrentKilometers: rounded(distanceKilometers),
                accuracyRadiusKilometers: rounded(
                    place.accuracyRadiusMeters / 1_000
                ),
                effectiveProximityRadiusKilometers: rounded(
                    effectiveProximityRadiusKilometers
                ),
                isCurrentLocationInsideProximityRadius:
                    distanceKilometers <= effectiveProximityRadiusKilometers,
                lastVisitedAtISO8601: statistics?.lastVisitedAt?.ISO8601Format(),
                visitCount: statistics?.visitCount ?? 0
            )
        }.sorted { $0.locationKey < $1.locationKey }
    }

    static func selectedDayHistoryContext(
        context: EntryPromptContext,
        references: EntryPromptReferences
    ) -> SelectedDayHistoryPromptContext {
        let placeKeysByID = Dictionary(
            uniqueKeysWithValues: references.placesByKey.map { key, place in
                (place.id, key)
            }
        )
        let personKeysByID = Dictionary(
            uniqueKeysWithValues: references.peopleByKey.map { key, person in
                (person.id, key)
            }
        )
        let entries = context.selectedDayEntries.enumerated().map { index, entry in
            let startTimeZone = TimeZone(
                identifier: entry.startTimeZoneIdentifier
            ) ?? .current
            let endTimeZone = TimeZone(
                identifier: entry.endTimeZoneIdentifier
            ) ?? .current
            let transit = entry.transitDetails.map { details in
                SelectedDayTransitPromptContext(
                    canonicalTransitType: details.type,
                    origin: historyLocationContext(
                        entry: entry,
                        role: "transit-origin",
                        location: details.originLocation ?? details.originPlace?.location,
                        place: details.originPlace,
                        rawText: details.originRawText,
                        placeKeysByID: placeKeysByID,
                        references: references
                    ),
                    destination: historyLocationContext(
                        entry: entry,
                        role: "transit-destination",
                        location: details.destinationLocation ?? details.destinationPlace?.location,
                        place: details.destinationPlace,
                        rawText: details.destinationRawText,
                        placeKeysByID: placeKeysByID,
                        references: references
                    )
                )
            }
            let visit = entry.placeVisitDetails.map { details in
                SelectedDayVisitPromptContext(
                    location: historyLocationContext(
                        entry: entry,
                        role: "visit-location",
                        location: details.location ?? details.place?.location,
                        place: details.place,
                        rawText: details.placeRawText,
                        placeKeysByID: placeKeysByID,
                        references: references
                    )
                )
            }
            let workout = entry.workoutDetails.map { details in
                SelectedDayWorkoutPromptContext(
                    activityName: details.activityName,
                    movementKind: details.movementKind.rawValue,
                    location: historyLocationContext(
                        entry: entry,
                        role: "workout-location",
                        location: details.sourceLocation ?? details.place?.location,
                        place: details.place,
                        rawText: nil,
                        placeKeysByID: placeKeysByID,
                        references: references
                    ),
                    origin: historyLocationContext(
                        entry: entry,
                        role: "workout-origin",
                        location: details.originLocation ?? details.originPlace?.location,
                        place: details.originPlace,
                        rawText: nil,
                        placeKeysByID: placeKeysByID,
                        references: references
                    ),
                    destination: historyLocationContext(
                        entry: entry,
                        role: "workout-destination",
                        location: details.destinationLocation ?? details.destinationPlace?.location,
                        place: details.destinationPlace,
                        rawText: nil,
                        placeKeysByID: placeKeysByID,
                        references: references
                    ),
                    distanceKilometers: details.distanceMeters.map {
                        rounded($0 / 1_000)
                    }
                )
            }
            let wakeUp = entry.kind == .wakeUp
                ? SelectedDayWakeUpPromptContext(
                    sleepDurationMinutes: entry.sleepDurationSeconds.map {
                        rounded($0 / 60)
                    }
                )
                : nil
            let reviewedFields: [String]
            switch entry.kind {
            case .transit:
                reviewedFields = entry.transitDetails?.fieldReviews.map(
                    \.field.rawValue
                ) ?? []
            case .placeVisit:
                reviewedFields = entry.placeVisitDetails?.fieldReviews.map(
                    \.field.rawValue
                ) ?? []
            case .workout:
                reviewedFields = entry.workoutDetails?.fieldReviews.map(
                    \.field.rawValue
                ) ?? []
            case .wakeUp:
                reviewedFields = []
            }

            return SelectedDayEntryPromptContext(
                entryKey: "selected-day-entry-\(index + 1)",
                relativeDay: relativeDayLabel(
                    for: entry,
                    selectedDay: context.selectedDay
                ),
                entryKind: entry.kind.rawValue,
                entryKindNeedsReview: entry.entryKindReviewReason != nil,
                reviewedFields: reviewedFields.sorted(),
                startTimeISO8601: entry.startTime.map {
                    iso8601String($0, in: startTimeZone)
                },
                endTimeISO8601: entry.endTime.map {
                    iso8601String($0, in: endTimeZone)
                },
                startTimeZoneIdentifier: entry.startTimeZoneIdentifier,
                endTimeZoneIdentifier: entry.endTimeZoneIdentifier,
                timeConfidence: entry.timeConfidence.rawValue,
                transit: transit,
                placeVisit: visit,
                workout: workout,
                wakeUp: wakeUp,
                peopleKeys: entry.people.compactMap { personKeysByID[$0.id] }.sorted()
            )
        }

        return SelectedDayHistoryPromptContext(
            entries: entries
        )
    }

    static func historyLocationContext(
        entry: LogEntry,
        role: String,
        location: Location?,
        place: Place?,
        rawText: String?,
        placeKeysByID: [UUID: String],
        references: EntryPromptReferences
    ) -> SelectedDayLocationPromptContext? {
        guard let location,
              let locationKey = references.historyLocationKey(
                entryID: entry.id,
                role: role
              ) else {
            return nil
        }
        return SelectedDayLocationPromptContext(
            locationKey: locationKey,
            savedPlaceKey: place.flatMap { placeKeysByID[$0.id] },
            displayName: place?.name ?? location.preferredName ?? rawText,
            compactAddress: location.compactAddress,
            fullAddress: location.formattedAddress,
            timeZoneIdentifier: location.timeZoneIdentifier
        )
    }

    static func relativeDayLabel(
        for entry: LogEntry,
        selectedDay: TimelineDayKey
    ) -> String {
        let anchor = entry.kind == .wakeUp
            ? entry.endTime ?? entry.startTime ?? entry.createdAt
            : entry.startTime ?? entry.endTime ?? entry.createdAt
        let timeZone = TimeZone(
            identifier: entry.kind == .wakeUp
                ? entry.endTimeZoneIdentifier
                : entry.startTimeZoneIdentifier
        ) ?? TimeZone(
            identifier: entry.creationTimeZoneIdentifier
        ) ?? .current
        let day = TimelineDayKey(date: anchor, timeZone: timeZone)
        if day == selectedDay.addingDays(-1) { return "previousDay" }
        if day == selectedDay { return "selectedDay" }
        if day == selectedDay.addingDays(1) { return "nextDay" }
        return "nearbyDay"
    }

    static func peopleContext(
        _ references: EntryPromptReferences
    ) -> [PersonPromptContext] {
        references.peopleByKey.map { key, person in
            PersonPromptContext(
                personKey: key,
                name: person.name,
                aliases: person.aliases
            )
        }.sorted { $0.personKey < $1.personKey }
    }

    static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    static func encoded<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"error":"Could not encode entry context"}"#
        }
        return string
    }

    static func toolTranscript(
        from entries: ArraySlice<Transcript.Entry>
    ) -> String? {
        var sections: [String] = []

        for entry in entries {
            switch entry {
            case .toolCalls(let calls):
                sections.append(contentsOf: calls.map { call in
                    """
                    TOOL CALL
                    id: \(call.id)
                    name: \(call.toolName)
                    arguments:
                    \(call.arguments.jsonString)
                    """
                })
            case .toolOutput(let output):
                sections.append(
                    """
                    TOOL OUTPUT
                    id: \(output.id)
                    name: \(output.toolName)
                    output:
                    \(segmentText(output.segments))
                    """
                )
            default:
                continue
            }
        }

        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    static func segmentText(_ segments: [Transcript.Segment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let text):
                text.content
            case .structure(let structure):
                structure.content.jsonString
            default:
                segment.description
            }
        }.joined(separator: "\n")
    }
}
