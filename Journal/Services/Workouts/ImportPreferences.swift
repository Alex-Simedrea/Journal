//
//  WorkoutImportPreferences.swift
//  Journal
//

import Foundation
import HealthKit

enum WorkoutImportPreferences {
    private static let cutoffKey = "healthkit.workouts.cutoff"
    private static let anchorKey = "healthkit.workouts.anchor"
    private static let excludedUUIDsKey = "healthkit.workouts.excluded-uuids"

    static func cutoff(now: Date = .now) -> Date {
        let defaults = UserDefaults.standard
        if let stored = defaults.object(forKey: cutoffKey) as? Date {
            return stored
        }

        let cutoff = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: -30,
            to: now
        ) ?? now.addingTimeInterval(-30 * 24 * 60 * 60)
        defaults.set(cutoff, forKey: cutoffKey)
        return cutoff
    }

    static func anchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: anchorKey) else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: HKQueryAnchor.self,
            from: data
        )
    }

    static func save(anchor: HKQueryAnchor) throws {
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: anchor,
            requiringSecureCoding: true
        )
        UserDefaults.standard.set(data, forKey: anchorKey)
    }

    static func resetAnchor() {
        UserDefaults.standard.removeObject(forKey: anchorKey)
    }

    static func isExcluded(_ uuid: UUID) -> Bool {
        excludedUUIDs().contains(uuid)
    }

    static func exclude(_ uuid: UUID) {
        var values = excludedUUIDs()
        values.insert(uuid)
        saveExcludedUUIDs(values)
    }

    static func removeExclusion(_ uuid: UUID) {
        var values = excludedUUIDs()
        values.remove(uuid)
        saveExcludedUUIDs(values)
    }

    private static func excludedUUIDs() -> Set<UUID> {
        let values = UserDefaults.standard.stringArray(
            forKey: excludedUUIDsKey
        ) ?? []
        return Set(values.compactMap(UUID.init(uuidString:)))
    }

    private static func saveExcludedUUIDs(_ values: Set<UUID>) {
        UserDefaults.standard.set(
            values.map(\.uuidString).sorted(),
            forKey: excludedUUIDsKey
        )
    }
}
