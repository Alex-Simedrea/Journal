import Foundation

struct ComposerTextSegment: Equatable, Sendable {
    let text: String
    let range: Range<Int>
}

enum GuidedComposerLexer {
    static func segments(in text: String) -> [ComposerTextSegment] {
        var result: [ComposerTextSegment] = []
        var index = text.startIndex

        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }
            guard index < text.endIndex else { break }

            if text[index] == "," || text[index] == "&" {
                let end = text.index(after: index)
                result.append(
                    segment(text: text, range: index..<end)
                )
                index = end
                continue
            }

            let start = index
            while index < text.endIndex,
                  !text[index].isWhitespace,
                  text[index] != ",",
                  text[index] != "&" {
                index = text.index(after: index)
            }
            result.append(segment(text: text, range: start..<index))
        }
        return result
    }

    private static func segment(
        text: String,
        range: Range<String.Index>
    ) -> ComposerTextSegment {
        ComposerTextSegment(
            text: String(text[range]),
            range: text.distance(
                from: text.startIndex,
                to: range.lowerBound
            )..<text.distance(
                from: text.startIndex,
                to: range.upperBound
            )
        )
    }
}
