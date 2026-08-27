import Foundation

/// Explicit JSON storage for Codable values that SwiftData should treat as
/// ordinary binary data instead of using its collection materializer.
nonisolated enum PersistedJSON {
    static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data?
    ) -> Value? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func encode<Value: Encodable>(_ value: Value) -> Data? {
        try? JSONEncoder().encode(value)
    }
}
