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
}
