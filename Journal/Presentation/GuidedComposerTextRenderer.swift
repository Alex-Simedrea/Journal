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
            result[range].foregroundColor = color(for: token.role)
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

    private static func color(
        for role: ComposerValueRole
    ) -> Color {
        switch role {
        case .leading: .purple
        case .location: .green
        case .time, .duration: .orange
        case .person: .pink
        case .connector: .secondary
        }
    }
}
