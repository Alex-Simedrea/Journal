import Foundation
import Testing

@testable import Journal

@Suite("Summary map snapshot cache")
struct SummaryMapSnapshotTests {
    @Test("A rendered snapshot survives a new store instance")
    func diskHitAcrossStores() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = InvocationCounter()
        let expected = Data("rendered map".utf8)
        let request = request(slot: "day-2026-8-5", version: 1)

        let first = SummaryMapSnapshotStore(
            directory: directory,
            renderer: { _ in
                await counter.increment()
                return expected
            }
        )
        _ = try await first.data(for: request)

        let second = SummaryMapSnapshotStore(
            directory: directory,
            renderer: { _ in
                await counter.increment()
                return Data("unexpected rerender".utf8)
            }
        )
        let loaded = try await second.data(for: request)
        let renderCount = await counter.value

        #expect(loaded == expected)
        #expect(renderCount == 1)
    }

    @Test("Changing map content invalidates the stable day slot")
    func contentInvalidation() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SummaryMapSnapshotStore(
            directory: directory,
            renderer: { request in Data(request.contentHash.utf8) }
        )
        let oldRequest = request(slot: "day-2026-8-5", version: 1)
        let newRequest = request(slot: "day-2026-8-5", version: 2)

        _ = try await store.data(for: oldRequest)
        _ = try await store.data(for: newRequest)

        let slot = directory.appending(
            path: newRequest.slotHash,
            directoryHint: .isDirectory
        )
        let contentDirectories = try FileManager.default.contentsOfDirectory(
            at: slot,
            includingPropertiesForKeys: nil
        )
        #expect(contentDirectories.map(\.lastPathComponent) == [
            newRequest.contentHash,
        ])
    }

    @Test("Concurrent readers share one render task")
    func requestDeduplication() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = InvocationCounter()
        let store = SummaryMapSnapshotStore(
            directory: directory,
            renderer: { _ in
                await counter.increment()
                try await Task.sleep(for: .milliseconds(40))
                return Data("one render".utf8)
            }
        )
        let request = request(slot: "day-2026-8-5", version: 1)

        async let first = store.data(for: request)
        async let second = store.data(for: request)
        let values = try await [first, second]
        let renderCount = await counter.value

        #expect(values[0] == values[1])
        #expect(renderCount == 1)
    }

    @Test("Disk storage is trimmed to the configured byte cap")
    func byteCap() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SummaryMapSnapshotStore(
            directory: directory,
            maximumBytes: 10,
            renderer: { request in
                Data(repeating: UInt8(request.content.renderVersion), count: 8)
            }
        )

        _ = try await store.data(for: request(slot: "first", version: 1))
        _ = try await store.data(for: request(slot: "second", version: 2))

        let total = regularFileSize(in: directory)
        #expect(total <= 10)
    }

    private func request(
        slot: String,
        version: Int
    ) -> SummaryMapSnapshotRequest {
        SummaryMapSnapshotRequest(
            slotID: slot,
            content: SummaryMapSnapshotContent(
                renderVersion: version,
                camera: .place(
                    center: SummaryMapCoordinate(latitude: 44, longitude: 28),
                    diameterMeters: 320
                ),
                markers: [],
                paths: []
            ),
            variant: .init(
                pixelWidth: 300,
                pixelHeight: 300,
                scale: 3,
                appearance: .light
            )
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "SummaryMapSnapshotTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }

    private func regularFileSize(in directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else { return 0 }
        var result = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
            ])
            if values?.isRegularFile == true {
                result += values?.fileSize ?? 0
            }
        }
        return result
    }
}

private actor InvocationCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
