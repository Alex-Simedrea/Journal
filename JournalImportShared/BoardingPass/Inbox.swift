import CryptoKit
import Foundation
import PassKit
import ZIPFoundation

enum BoardingPassImportInbox {
    static func store(_ pendingImport: PendingBoardingPassImport) throws {
        let directory = try inboxDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(pendingImport)
        let destination = fileURL(for: pendingImport.id, in: directory)
        try data.write(to: destination, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )
    }

    static func oldest() throws -> PendingBoardingPassImport? {
        let directory = try inboxDirectory()
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return nil
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let sortedURLs = try urls
            .filter { $0.pathExtension == "json" }
            .map { url in
                (url, try url.resourceValues(forKeys: [.contentModificationDateKey]))
            }
            .sorted {
                ($0.1.contentModificationDate ?? .distantPast)
                    < ($1.1.contentModificationDate ?? .distantPast)
            }
            .map(\.0)

        for url in sortedURLs {
            do {
                return try decoder.decode(
                    PendingBoardingPassImport.self,
                    from: Data(contentsOf: url)
                )
            } catch {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return nil
    }

    static func remove(id: UUID) throws {
        let directory = try inboxDirectory()
        let url = fileURL(for: id, in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func inboxDirectory() throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: JournalImportConfiguration
                .appGroupIdentifier
        ) else {
            throw BoardingPassImportError.unavailableSharedContainer
        }
        return container.appending(
            path: "BoardingPassImportInbox",
            directoryHint: .isDirectory
        )
    }

    private static func fileURL(for id: UUID, in directory: URL) -> URL {
        directory.appending(path: id.uuidString).appendingPathExtension("json")
    }
}
