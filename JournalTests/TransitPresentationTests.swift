import Testing

@testable import Journal

@Suite("Transit presentation")
struct TransitPresentationTests {
    @Test("Every seeded type has a dedicated symbol")
    func seededTypesHaveDedicatedSymbols() {
        let names = [
            "Walk", "Bicycle", "Scooter", "Motorcycle", "Car", "Taxi",
            "Ride share", "Uber", "Bolt", "Lyft", "Bus", "Train",
            "Metro", "Tram", "Ferry", "Flight",
        ]

        for name in names {
            #expect(
                TransitPresentationCatalog.presentation(for: name)
                    .systemImageName != "arrow.triangle.swap"
            )
        }
    }

    @Test("Unknown types use the fallback symbol")
    func unknownTypeFallback() {
        #expect(
            TransitPresentationCatalog.presentation(for: "Teleport")
                .systemImageName == "arrow.triangle.swap"
        )
    }

    @Test("Timeline locations display their address instead of model raw text")
    @MainActor
    func timelineUsesAddress() {
        let entry = LogEntry(kind: .transit, needsReview: false)
        entry.transitDetails = TransitDetails(
            type: "Bus",
            originLocation: Location(
                latitude: 45.65,
                longitude: 25.60,
                compactAddress: "TD Copy, Brașov"
            ),
            originRawText: "TD Copy",
            destinationLocation: Location(
                latitude: 45.66,
                longitude: 25.61,
                displayName: "origin of the walk",
                formattedAddress: "Piața Revoluției, Bucharest, Romania",
                compactAddress: "Piața Revoluției, Bucharest"
            ),
            destinationRawText: "origin of the walk"
        )

        let snapshot = TimelineEntrySnapshot(entry: entry)

        #expect(snapshot.destination == "Piața Revoluției")
        #expect(snapshot.destination != entry.transitDetails?.destinationRawText)
    }

    @Test("Timeline addresses remove cities but preserve street numbers")
    func timelineAddressFormatting() {
        #expect(
            Location(
                latitude: 0,
                longitude: 0,
                compactAddress: "Piața Revoluției, Bucharest"
            ).timelineAddress == "Piața Revoluției"
        )
        #expect(
            Location(
                latitude: 0,
                longitude: 0,
                compactAddress: "Strada Sitarului, 16, Brașov"
            ).timelineAddress == "Strada Sitarului, 16"
        )
        #expect(
            Location(
                latitude: 0,
                longitude: 0,
                compactAddress: "Strada Sitarului, 16"
            ).timelineAddress == "Strada Sitarului, 16"
        )
    }
}
