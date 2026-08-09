import Foundation
import UniformTypeIdentifiers

@MainActor
enum SharedPlainTextLoader {
    static func load(from provider: NSItemProvider) async throws -> String {
        let identifiers = textTypeIdentifiers(from: provider)
        var lastError: (any Error)?

        for identifier in identifiers {
            do {
                let data = try await loadData(
                    from: provider,
                    typeIdentifier: identifier
                )
                if let text = decode(data) {
                    return text
                }
            } catch {
                lastError = error
            }

            do {
                let data = try await loadFileData(
                    from: provider,
                    typeIdentifier: identifier
                )
                if let text = decode(data) {
                    return text
                }
            } catch {
                lastError = error
            }
        }

        if provider.canLoadObject(ofClass: NSString.self) {
            do {
                let text = try await loadString(from: provider)
                if let text = nonempty(text as String) {
                    return text
                }
            } catch {
                lastError = error
            }
        }

        if let lastError { throw lastError }
        throw BoardingPassImportError.invalidFlightSummary
    }

    private static func textTypeIdentifiers(
        from provider: NSItemProvider
    ) -> [String] {
        let registered = provider.registeredTypeIdentifiers.filter {
            UTType($0)?.conforms(to: .text) == true
        }
        let sorted = registered.sorted { lhs, rhs in
            let lhsIsPlainText = UTType(lhs)?.conforms(to: .plainText) == true
            let rhsIsPlainText = UTType(rhs)?.conforms(to: .plainText) == true
            return lhsIsPlainText && !rhsIsPlainText
        }
        return sorted.isEmpty ? [UTType.plainText.identifier] : sorted
    }

    private static func loadFileData(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(
                forTypeIdentifier: typeIdentifier
            ) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    do {
                        continuation.resume(
                            returning: try Data(contentsOf: url)
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(
                        throwing: BoardingPassImportError.invalidFlightSummary
                    )
                }
            }
        }
    }

    private static func loadString(
        from provider: NSItemProvider
    ) async throws -> NSString {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: NSString.self) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let text = item as? NSString {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(
                        throwing: BoardingPassImportError.invalidFlightSummary
                    )
                }
            }
        }
    }

    private static func loadData(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(
                forTypeIdentifier: typeIdentifier
            ) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(
                        throwing: BoardingPassImportError.invalidFlightSummary
                    )
                }
            }
        }
    }

    private static func decode(_ data: Data) -> String? {
        let unicodeEncodings = unicodeEncodings(for: data)
        let encodings: [String.Encoding] = data.contains(0)
            ? unicodeEncodings + [.utf8, .isoLatin1]
            : [.utf8] + unicodeEncodings + [.isoLatin1]
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding),
               !text.contains("\0"),
               let text = nonempty(text) {
                return text
            }
        }
        return nil
    }

    private static func unicodeEncodings(
        for data: Data
    ) -> [String.Encoding] {
        let bytes = Array(data.prefix(256))
        if bytes.starts(with: [0xFF, 0xFE]) {
            return [.utf16LittleEndian, .utf16, .utf16BigEndian, .utf32]
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            return [.utf16BigEndian, .utf16, .utf16LittleEndian, .utf32]
        }

        let evenNulls = bytes.enumerated().count { offset, byte in
            offset.isMultiple(of: 2) && byte == 0
        }
        let oddNulls = bytes.enumerated().count { offset, byte in
            !offset.isMultiple(of: 2) && byte == 0
        }
        if oddNulls > evenNulls {
            return [.utf16LittleEndian, .utf16BigEndian, .utf16, .utf32]
        }
        if evenNulls > oddNulls {
            return [.utf16BigEndian, .utf16LittleEndian, .utf16, .utf32]
        }
        return [.utf16, .utf16LittleEndian, .utf16BigEndian, .utf32]
    }

    private static func nonempty(_ value: String) -> String? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : value
    }
}
