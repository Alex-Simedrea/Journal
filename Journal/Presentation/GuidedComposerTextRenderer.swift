import SwiftUI

enum GuidedComposerTextRenderer {
    static func render(
        _ text: String,
        tokens: [ComposerToken],
        ranges: [UUID: Range<Int>]
    ) -> AttributedString {
        var result = AttributedString(text)
        for token in tokens {
            guard let offsets = ranges[token.id],
                  let range = attributedRange(
                      for: offsets,
                      in: result
                  ) else {
                continue
            }
            result[range].foregroundColor = color(for: token)
        }
        return result
    }

    private static func attributedRange(
        for offsets: Range<Int>,
        in text: AttributedString
    ) -> Range<AttributedString.Index>? {
        guard let lower = text.characters.index(
            text.startIndex,
            offsetBy: offsets.lowerBound,
            limitedBy: text.endIndex
        ), let upper = text.characters.index(
            text.startIndex,
            offsetBy: offsets.upperBound,
            limitedBy: text.endIndex
        ) else {
            return nil
        }
        return lower..<upper
    }

    private static func color(for token: ComposerToken) -> Color {
        switch token.value {
        case .leading(.transit(let canonicalName)):
            TransitPresentationCatalog.presentation(
                for: canonicalName
            ).color
        case .leading(.placeVisit):
            .indigo
        case .location(let location, _):
            PlaceSymbols.symbol(for: location.systemImage).primary
        case .time, .duration:
            .orange
        case .person:
            .blue
        case .connector:
            .secondary
        }
    }
}
