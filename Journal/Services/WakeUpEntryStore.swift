//
//  WakeUpEntryStore.swift
//  Journal
//

import Foundation
import SwiftData

@MainActor
enum WakeUpEntryStore {
    static func synchronize(
        snapshots: [HealthKitWakeUpSnapshot],
        in modelContext: ModelContext
    ) throws {
        let existingEntries = try modelContext.fetch(
            FetchDescriptor<LogEntry>()
        ).filter { $0.kind == .wakeUp }
        var entriesBySourceUUID = Dictionary(
            uniqueKeysWithValues: existingEntries.compactMap { entry in
                entry.wakeUpSourceSampleUUID.map { ($0, entry) }
            }
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
            let entry = entriesBySourceUUID.removeValue(
                forKey: snapshot.sourceSampleUUID
            ) ?? LogEntry(
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

            entry.kind = .wakeUp
            entry.startTime = snapshot.sleepStart
            entry.endTime = snapshot.wakeTime
            entry.startTimeZoneIdentifier = timeZoneIdentifier
            entry.endTimeZoneIdentifier = timeZoneIdentifier
            entry.timeConfidence = .explicit
            entry.needsReview = false
            entry.entryKindReviewReason = nil
            entry.wakeUpSourceSampleUUID = snapshot.sourceSampleUUID
            entry.sleepDurationSeconds = snapshot.sleepDurationSeconds
            entry.weather = nil
            entry.endWeather = nil
            entry.photoReferences = []
            entry.people = []

            if entry.modelContext == nil {
                modelContext.insert(entry)
            }
        }
    }
}
