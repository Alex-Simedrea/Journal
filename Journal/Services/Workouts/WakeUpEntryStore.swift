//
//  WakeUpEntryStore.swift
//  Journal
//

import Foundation
import SwiftData

nonisolated enum WakeUpEntryStore {
    static func synchronize(
        snapshots: [HealthKitWakeUpSnapshot],
        in modelContext: ModelContext
    ) throws {
        let existingEntries = try modelContext.fetch(
            FetchDescriptor<LogEntry>()
        ).filter { $0.kind == .wakeUp }
        // Historical restores can contain multiple entries for one HealthKit
        // sample; source UUID is not a unique schema attribute.
        var entriesBySourceUUID = Dictionary(
            existingEntries.compactMap { entry in
                entry.wakeUpSourceSampleUUID.map { ($0, entry) }
            }, uniquingKeysWith: { first, _ in first }
        )
        let currentSourceUUIDs = Set(snapshots.map(\.sourceSampleUUID))

        for entry in existingEntries where entry.wakeUpSourceSampleUUID.map(
            { !currentSourceUUIDs.contains($0) }
        ) ?? true {
            modelContext.delete(entry)
        }

        for snapshot in snapshots {
            let timeZoneIdentifier = snapshot.timeZoneIdentifier
                ?? TimeZone.current.identifier
            let entry = entriesBySourceUUID[snapshot.sourceSampleUUID] ?? LogEntry(
                kind: .wakeUp,
                startTime: snapshot.sleepStart,
                endTime: snapshot.wakeTime,
                startTimeZoneIdentifier: timeZoneIdentifier,
                endTimeZoneIdentifier: timeZoneIdentifier,
                creationTimeZoneIdentifier: timeZoneIdentifier,
                timeConfidence: .explicit,
                wakeUpSourceSampleUUID: snapshot.sourceSampleUUID,
                sleepDurationSeconds: snapshot.sleepDurationSeconds,
                needsReview: false
            )

            entriesBySourceUUID[snapshot.sourceSampleUUID] = entry
            if entry.modelContext == nil {
                modelContext.insert(entry)
            } else {
                updateExistingEntry(
                    entry,
                    from: snapshot,
                    timeZoneIdentifier: timeZoneIdentifier
                )
            }
        }
    }

    private static func updateExistingEntry(
        _ entry: LogEntry,
        from snapshot: HealthKitWakeUpSnapshot,
        timeZoneIdentifier: String
    ) {
        if entry.kind != .wakeUp { entry.kind = .wakeUp }
        if entry.startTime != snapshot.sleepStart {
            entry.startTime = snapshot.sleepStart
        }
        if entry.endTime != snapshot.wakeTime {
            entry.endTime = snapshot.wakeTime
        }
        if entry.startTimeZoneIdentifier != timeZoneIdentifier {
            entry.startTimeZoneIdentifier = timeZoneIdentifier
        }
        if entry.endTimeZoneIdentifier != timeZoneIdentifier {
            entry.endTimeZoneIdentifier = timeZoneIdentifier
        }
        if entry.timeConfidence != .explicit {
            entry.timeConfidence = .explicit
        }
        if entry.needsReview { entry.needsReview = false }
        if entry.entryKindReviewReason != nil {
            entry.entryKindReviewReason = nil
        }
        if entry.wakeUpSourceSampleUUID != snapshot.sourceSampleUUID {
            entry.wakeUpSourceSampleUUID = snapshot.sourceSampleUUID
        }
        if entry.sleepDurationSeconds != snapshot.sleepDurationSeconds {
            entry.sleepDurationSeconds = snapshot.sleepDurationSeconds
        }
        if entry.weather != nil { entry.weather = nil }
        if entry.endWeather != nil { entry.endWeather = nil }
        if !entry.photoReferences.isEmpty { entry.photoReferences = [] }
        if !entry.people.isEmpty { entry.people = [] }
    }
}
