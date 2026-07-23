//
//  TransitTypeSeeder.swift
//  Journal
//

import Foundation
import SwiftData

enum TransitTypeSeeder {
    static func seedIfNeeded(in modelContext: ModelContext) throws {
        let storedTypes = try modelContext.fetch(FetchDescriptor<TransitType>())
        var storedTypesByName: [String: TransitType] = [:]
        for storedType in storedTypes {
            storedTypesByName[normalize(storedType.canonicalName)] = storedType
        }

        migrateLegacyRideShareAliases(in: storedTypesByName[normalize("Ride share")])

        for definition in defaults {
            let normalizedName = normalize(definition.canonicalName)

            if let storedType = storedTypesByName[normalizedName] {
                mergeMissingAliases(definition.aliases, into: storedType)
                continue
            }

            let transitType = TransitType(
                canonicalName: definition.canonicalName,
                aliases: definition.aliases,
                routingMode: definition.routingMode
            )
            modelContext.insert(transitType)
            storedTypesByName[normalizedName] = transitType
        }

        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    private static func mergeMissingAliases(
        _ aliases: [String],
        into transitType: TransitType
    ) {
        let storedAliases = Set(transitType.aliases.map(normalize))
        transitType.aliases.append(contentsOf: aliases.filter {
            !storedAliases.contains(normalize($0))
        })
    }

    private static func migrateLegacyRideShareAliases(in transitType: TransitType?) {
        guard let transitType else { return }

        let serviceSpecificAliases = Set([
            "uber", "uver", "bolt", "lyft", "cab", "taxi",
        ])
        transitType.aliases.removeAll {
            serviceSpecificAliases.contains(normalize($0))
        }
    }

    nonisolated private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Definition {
        let canonicalName: String
        let aliases: [String]
        let routingMode: TransitRoutingMode

        init(
            _ canonicalName: String,
            aliases: [String],
            routingMode: TransitRoutingMode = .automobile
        ) {
            self.canonicalName = canonicalName
            self.aliases = aliases
            self.routingMode = routingMode
        }
    }

    private static let defaults = [
        Definition(
            "Walk",
            aliases: ["walk", "walking", "on foot"],
            routingMode: .walking
        ),
        Definition(
            "Bicycle",
            aliases: ["bike", "bicycle", "cycling", "cycle"]
        ),
        Definition(
            "Scooter",
            aliases: ["scooter", "e-scooter", "electric scooter"]
        ),
        Definition(
            "Motorcycle",
            aliases: ["motorcycle", "motorbike", "motor bike"]
        ),
        Definition(
            "Car",
            aliases: ["car", "drive", "drove", "driving"]
        ),
        Definition(
            "Taxi",
            aliases: ["taxi", "cab"]
        ),
        Definition(
            "Ride share",
            aliases: ["ride share", "rideshare", "ride hailing", "ride-hailing"]
        ),
        Definition(
            "Uber",
            aliases: ["uber", "uver"]
        ),
        Definition(
            "Bolt",
            aliases: ["bolt"]
        ),
        Definition(
            "Lyft",
            aliases: ["lyft"]
        ),
        Definition(
            "Bus",
            aliases: ["bus", "coach"]
        ),
        Definition(
            "Train",
            aliases: ["train", "rail"]
        ),
        Definition(
            "Metro",
            aliases: ["metro", "subway", "underground"]
        ),
        Definition(
            "Tram",
            aliases: ["tram", "streetcar"]
        ),
        Definition(
            "Ferry",
            aliases: ["ferry", "boat"]
        ),
        Definition(
            "Flight",
            aliases: ["flight", "plane", "airplane", "aeroplane", "flying"]
        ),
    ]
}
