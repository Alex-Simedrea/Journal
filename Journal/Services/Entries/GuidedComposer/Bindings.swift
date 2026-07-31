import Foundation

enum GuidedComposerBindingReconciler {
    static func mergedTokenMemory(
        _ tokens: [ComposerToken],
        limit: Int = 200
    ) -> [ComposerToken] {
        var result: [ComposerToken] = []
        for token in tokens.reversed() {
            let displayText = GuidedComposerNormalization.text(
                token.displayText
            )
            guard !result.contains(where: {
                $0.role == token.role
                    && $0.value == token.value
                    && GuidedComposerNormalization.text($0.displayText)
                        == displayText
            }) else {
                continue
            }
            result.append(token)
        }
        return Array(result.reversed().suffix(limit))
    }

    static func bindings(
        for tokens: [ComposerToken],
        insertedRange: Range<Int>,
        in text: String
    ) -> [ComposerSemanticBinding] {
        let source = IntegerIndexedText(text)
        var offset = insertedRange.lowerBound
        let upperBound = min(insertedRange.upperBound, source.count)
        var result: [ComposerSemanticBinding] = []

        for token in tokens {
            while offset < upperBound,
                  source.character(at: offset)?.isWhitespace == true {
                offset += 1
            }
            let tokenEnd = min(offset + token.displayText.count, upperBound)
            guard tokenEnd > offset else { continue }
            result.append(
                ComposerSemanticBinding(
                    token: token,
                    range: offset..<tokenEnd
                )
            )
            offset = tokenEnd
        }
        return result
    }

    static func reconciled(
        _ bindings: [ComposerSemanticBinding],
        oldText: String,
        newText: String
    ) -> [ComposerSemanticBinding] {
        guard oldText != newText else { return bindings }
        let oldCharacters = Array(oldText)
        let newCharacters = Array(newText)
        var commonPrefix = 0
        while commonPrefix < oldCharacters.count,
              commonPrefix < newCharacters.count,
              oldCharacters[commonPrefix] == newCharacters[commonPrefix] {
            commonPrefix += 1
        }

        var commonSuffix = 0
        while commonSuffix < oldCharacters.count - commonPrefix,
              commonSuffix < newCharacters.count - commonPrefix,
              oldCharacters[oldCharacters.count - commonSuffix - 1]
                == newCharacters[newCharacters.count - commonSuffix - 1] {
            commonSuffix += 1
        }

        let oldEdit = commonPrefix..<(oldCharacters.count - commonSuffix)
        let newEdit = commonPrefix..<(newCharacters.count - commonSuffix)
        let delta = newEdit.count - oldEdit.count

        return bindings.compactMap { binding in
            if binding.range.upperBound <= oldEdit.lowerBound {
                return binding
            }
            if binding.range.lowerBound >= oldEdit.upperBound {
                var shifted = binding
                shifted.range = (
                    binding.range.lowerBound + delta
                )..<(
                    binding.range.upperBound + delta
                )
                return shifted
            }
            return nil
        }
    }

    static func merged(
        _ bindings: [ComposerSemanticBinding]
    ) -> [ComposerSemanticBinding] {
        var result: [ComposerSemanticBinding] = []
        for binding in bindings.reversed() {
            guard !result.contains(where: {
                $0.range == binding.range
                    && $0.token.role == binding.token.role
            }) else {
                continue
            }
            result.append(binding)
        }
        return Array(result.reversed())
    }
}
