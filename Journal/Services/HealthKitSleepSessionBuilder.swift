//
//  HealthKitSleepSessionBuilder.swift
//  Journal
//

import Foundation

nonisolated struct HealthKitSleepSampleSnapshot: Hashable, Sendable {
    let uuid: UUID
    let startTime: Date
    let endTime: Date
    let timeZoneIdentifier: String?
    let isAsleep: Bool
}

nonisolated struct HealthKitWakeUpSnapshot: Hashable, Sendable {
    let sourceSampleUUID: UUID
    let sleepStart: Date
    let wakeTime: Date
    let sleepDurationSeconds: TimeInterval
    let timeZoneIdentifier: String?
}

nonisolated enum HealthKitSleepSessionBuilder {
    static let maximumInterruption: TimeInterval = 90 * 60

    static func wakeUps(
        from samples: [HealthKitSleepSampleSnapshot],
        maximumInterruption: TimeInterval = maximumInterruption
    ) -> [HealthKitWakeUpSnapshot] {
        let asleepSamples = samples.filter {
            $0.isAsleep && $0.endTime > $0.startTime
        }.sorted(by: sampleOrder)

        var groups: [[HealthKitSleepSampleSnapshot]] = []
        var currentGroup: [HealthKitSleepSampleSnapshot] = []
        var currentEnd: Date?

        for sample in asleepSamples {
            if let currentEnd,
               sample.startTime.timeIntervalSince(currentEnd)
                > maximumInterruption {
                groups.append(currentGroup)
                currentGroup = []
            }

            currentGroup.append(sample)
            currentEnd = max(currentEnd ?? sample.endTime, sample.endTime)
        }

        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        return groups.compactMap(wakeUpSnapshot).sorted {
            $0.wakeTime < $1.wakeTime
        }
    }

    private static func wakeUpSnapshot(
        for samples: [HealthKitSleepSampleSnapshot]
    ) -> HealthKitWakeUpSnapshot? {
        guard let first = samples.first else { return nil }

        var intervalStart = first.startTime
        var intervalEnd = first.endTime
        var sleepDuration: TimeInterval = 0

        for sample in samples.dropFirst() {
            if sample.startTime <= intervalEnd {
                intervalEnd = max(intervalEnd, sample.endTime)
            } else {
                sleepDuration += intervalEnd.timeIntervalSince(intervalStart)
                intervalStart = sample.startTime
                intervalEnd = sample.endTime
            }
        }
        sleepDuration += intervalEnd.timeIntervalSince(intervalStart)

        let wakeTime = samples.map(\.endTime).max() ?? intervalEnd
        let terminalSamples = samples.filter { $0.endTime == wakeTime }
        guard let source = terminalSamples.sorted(by: sampleOrder).first else {
            return nil
        }

        return HealthKitWakeUpSnapshot(
            sourceSampleUUID: source.uuid,
            sleepStart: samples.map(\.startTime).min() ?? intervalStart,
            wakeTime: wakeTime,
            sleepDurationSeconds: sleepDuration,
            timeZoneIdentifier: source.timeZoneIdentifier
                ?? samples.reversed().compactMap(\.timeZoneIdentifier).first
        )
    }

    private static func sampleOrder(
        _ lhs: HealthKitSleepSampleSnapshot,
        _ rhs: HealthKitSleepSampleSnapshot
    ) -> Bool {
        if lhs.startTime != rhs.startTime {
            return lhs.startTime < rhs.startTime
        }
        if lhs.endTime != rhs.endTime {
            return lhs.endTime < rhs.endTime
        }
        return lhs.uuid.uuidString < rhs.uuid.uuidString
    }
}
