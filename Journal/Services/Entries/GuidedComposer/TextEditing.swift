import Foundation

struct GuidedComposerTextEditResult: Equatable, Sendable {
    let text: String
    let caretOffset: Int
    let insertedRange: Range<Int>
}

enum GuidedComposerTextEditor {
    static func accepting(
        _ replacement: String,
        in text: String,
        replacing range: Range<Int>
    ) -> GuidedComposerTextEditResult {
        let source = IntegerIndexedText(text)
        let range = source.clamped(range)
        var prefix = source.substring(in: 0..<range.lowerBound)
        var suffix = source.substring(in: range.upperBound..<source.count)
        var inserted = replacement

        if inserted.first == "," {
            while prefix.last?.isWhitespace == true {
                prefix.removeLast()
            }
        } else if prefix.last?.isWhitespace == false,
                  inserted.first?.isWhitespace != true {
            inserted = " " + inserted
        }
        if suffix.first?.isWhitespace == false,
           !beginsWithTightPunctuation(suffix),
           inserted.last?.isWhitespace != true {
            inserted += " "
        }
        if prefix.last?.isWhitespace == true,
           inserted.first?.isWhitespace == true {
            inserted.removeFirst()
        }
        if suffix.first?.isWhitespace == true,
           inserted.last?.isWhitespace == true {
            suffix.removeFirst()
        }

        let insertedStart = prefix.count
        let insertedEnd = insertedStart + inserted.count
        var result = GuidedComposerTextEditResult(
            text: prefix + inserted + suffix,
            caretOffset: insertedEnd,
            insertedRange: insertedStart..<insertedEnd
        )
        let editedSource = IntegerIndexedText(result.text)

        if result.caretOffset < editedSource.count,
           editedSource.character(at: result.caretOffset)?
            .isWhitespace == true {
            var caret = result.caretOffset
            while caret < editedSource.count,
                  editedSource.character(at: caret)?.isWhitespace == true {
                caret += 1
            }
            result = GuidedComposerTextEditResult(
                text: result.text,
                caretOffset: caret,
                insertedRange: result.insertedRange
            )
        } else if result.caretOffset == editedSource.count {
            result = GuidedComposerTextEditResult(
                text: result.text + " ",
                caretOffset: result.caretOffset + 1,
                insertedRange: result.insertedRange
            )
        }
        return result
    }

    private static func beginsWithTightPunctuation(_ value: String) -> Bool {
        guard let first = value.first else { return false }
        return ",.;:!?%)]}".contains(first)
    }
}
