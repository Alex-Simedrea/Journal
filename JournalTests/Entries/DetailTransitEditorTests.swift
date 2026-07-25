import Testing

@testable import Journal

@Suite("Entry detail transit type projection")
struct DetailTransitEditorTests {
    @Test("Seeded transit types follow the curated grid order")
    func curatedOrder() {
        let alphabeticalNames = EntryDetailTransitTypeProjection.curatedNames
            .sorted()

        let choices = EntryDetailTransitTypeProjection.choices(
            availableNames: alphabeticalNames,
            selectedName: "Train"
        )

        #expect(
            choices.map(\.name)
                == EntryDetailTransitTypeProjection.curatedNames
        )
    }

    @Test("Unknown selections are preserved after known types")
    func unknownSelection() {
        let choices = EntryDetailTransitTypeProjection.choices(
            availableNames: ["Bus", "Walk"],
            selectedName: "Teleport"
        )

        #expect(choices.map(\.name) == ["Walk", "Bus", "Teleport"])
    }

    @Test("Known selections are not duplicated by casing differences")
    func selectedTypeDeduplication() {
        let choices = EntryDetailTransitTypeProjection.choices(
            availableNames: ["Walk", "Bus"],
            selectedName: " walk "
        )

        #expect(choices.map(\.name) == ["Walk", "Bus"])
        #expect(
            EntryDetailTransitTypeProjection.matches("Walk", " walk ")
        )
    }

    @Test("Future stored types sort after the curated catalog")
    func futureTypes() {
        let choices = EntryDetailTransitTypeProjection.choices(
            availableNames: ["Zeppelin", "Bus", "Cable car"],
            selectedName: ""
        )

        #expect(
            choices.map(\.name) == ["Bus", "Cable car", "Zeppelin"]
        )
    }
}
