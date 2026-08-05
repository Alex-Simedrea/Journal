import SwiftUI
import Testing

@testable import Journal

@Suite("Guided composer text rendering")
struct GuidedComposerTextRendererTests {
    @Test("Semantic tokens use their domain presentation colors")
    func semanticTokenColors() throws {
        let transit = ComposerToken(
            displayText: "Bolt",
            value: .leading(.transit(canonicalName: "Bolt"))
        )
        let connector = ComposerToken(
            displayText: "from",
            value: .connector(.from)
        )
        let beach = ComposerLocationCandidate(
            id: "beach",
            displayName: "Beach",
            location: Location(latitude: 44.2, longitude: 28.6),
            systemImage: .beach,
            source: .savedPlace
        )
        let location = ComposerToken(
            displayText: "Beach",
            value: .location(beach, .origin)
        )
        let person = ComposerToken(
            displayText: "Emma",
            value: .person(ComposerPersonCandidate(
                id: UUID(),
                name: "Emma",
                aliases: [],
                contactIdentifier: nil,
                usageCount: 0
            ))
        )
        let text = "Bolt from Beach Emma"
        let rendered = GuidedComposerTextRenderer.render(
            text,
            tokens: [transit, connector, location, person],
            ranges: [
                transit.id: 0..<4,
                connector.id: 5..<9,
                location.id: 10..<15,
                person.id: 16..<20,
            ]
        )

        #expect(try foregroundColor(at: 0, in: rendered)
            == TransitPresentationCatalog.presentation(for: "Bolt").color)
        #expect(try foregroundColor(at: 5, in: rendered) == .secondary)
        #expect(try foregroundColor(at: 10, in: rendered)
            == PlaceSymbols.symbol(for: .beach).primary)
        #expect(try foregroundColor(at: 16, in: rendered) == .blue)
    }

    @Test("Place visit leading text uses indigo")
    func placeVisitLeadingColor() throws {
        let visit = ComposerToken(
            displayText: "Coffee",
            value: .leading(.placeVisit(description: "Coffee"))
        )
        let rendered = GuidedComposerTextRenderer.render(
            "Coffee",
            tokens: [visit],
            ranges: [visit.id: 0..<6]
        )

        #expect(try foregroundColor(at: 0, in: rendered) == .indigo)
    }

    @Test("Uber leading text uses the adaptive primary color")
    func uberLeadingColor() throws {
        let uber = ComposerToken(
            displayText: "Uber",
            value: .leading(.transit(canonicalName: "Uber"))
        )
        let rendered = GuidedComposerTextRenderer.render(
            "Uber",
            tokens: [uber],
            ranges: [uber.id: 0..<4]
        )

        #expect(try foregroundColor(at: 0, in: rendered) == .primary)
    }

    @Test("Unresolved text uses the adaptive primary color")
    func unresolvedTextColor() throws {
        let rendered = GuidedComposerTextRenderer.render(
            "unresolved",
            tokens: [],
            ranges: [:]
        )

        #expect(try foregroundColor(at: 0, in: rendered) == .primary)
    }

    private func foregroundColor(
        at offset: Int,
        in text: AttributedString
    ) throws -> Color? {
        let index = try #require(text.characters.index(
            text.startIndex,
            offsetBy: offset,
            limitedBy: text.endIndex
        ))
        let nextIndex = text.characters.index(after: index)
        return text[index..<nextIndex].foregroundColor
    }
}
