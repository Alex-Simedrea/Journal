import Foundation

/// A character-offset view over `String` for APIs that expose integer ranges.
///
/// Composer ranges are measured in user-perceived characters because
/// `AttributedString` selections use character indices. Keeping those
/// conversions here prevents parsers and editors from each implementing subtly
/// different clamping and indexing rules.
struct IntegerIndexedText {
    let value: String

    var count: Int {
        value.count
    }

    init(_ value: String) {
        self.value = value
    }

    func clamped(_ range: Range<Int>) -> Range<Int> {
        let lower = min(max(0, range.lowerBound), count)
        let upper = min(max(lower, range.upperBound), count)
        return lower..<upper
    }

    func substring(in range: Range<Int>) -> String {
        let range = clamped(range)
        let lower = value.index(value.startIndex, offsetBy: range.lowerBound)
        let upper = value.index(value.startIndex, offsetBy: range.upperBound)
        return String(value[lower..<upper])
    }

    func character(at offset: Int) -> Character? {
        guard !value.isEmpty, offset >= 0, offset < count else {
            return nil
        }
        return value[value.index(value.startIndex, offsetBy: offset)]
    }

    func character(before offset: Int) -> Character? {
        character(at: offset - 1)
    }

    func trimmingWhitespace(in range: Range<Int>) -> Range<Int> {
        var range = clamped(range)
        while range.lowerBound < range.upperBound,
              character(at: range.lowerBound)?.isWhitespace == true {
            range = (range.lowerBound + 1)..<range.upperBound
        }
        while range.upperBound > range.lowerBound,
              character(before: range.upperBound)?.isWhitespace == true {
            range = range.lowerBound..<(range.upperBound - 1)
        }
        return range
    }

    func nonWhitespaceIsCovered(by ranges: [Range<Int>]) -> Bool {
        for (offset, character) in value.enumerated()
        where !character.isWhitespace {
            guard ranges.contains(where: { $0.contains(offset) }) else {
                return false
            }
        }
        return true
    }
}
