import Foundation
import MapKit
import Testing

@testable import Journal

@Suite("Summary map snapshot cache")
struct SummaryMapSnapshotTests {
    @Test("Workout route geometry survives a new client instance")
    func workoutRouteDiskCache() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = InvocationCounter()
        let workoutUUID = UUID()
        let expected = [
            WorkoutCoordinateSnapshot(
                latitude: 44.43,
                longitude: 26.10,
                horizontalAccuracyMeters: 4
            ),
            WorkoutCoordinateSnapshot(
                latitude: 44.44,
                longitude: 26.11,
                horizontalAccuracyMeters: 5
            ),
        ]
        let first = HealthKitDayWorkoutRouteClient(
            loader: { _ in
                await counter.increment()
                return expected
            },
            cacheDirectory: directory
        )
        #expect(try await first.route(for: workoutUUID) == expected)

        let reopened = HealthKitDayWorkoutRouteClient(
            loader: { _ in
                await counter.increment()
                return []
            },
            cacheDirectory: directory
        )
        #expect(try await reopened.route(for: workoutUUID) == expected)
        #expect(await counter.value == 1)
    }

    @Test("Globe framing is unaffected by duplicate endpoint markers")
    func globeFramingIgnoresDuplicateCoordinates() throws {
        let route = [
            CLLocationCoordinate2D(latitude: 40.71, longitude: -74.01),
            CLLocationCoordinate2D(latitude: 47.50, longitude: -35.00),
            CLLocationCoordinate2D(latitude: 45.66, longitude: 25.61),
        ]
        let size = CGSize(width: 440, height: 290)
        let routeOnly = try #require(
            SummaryMapOverviewCamera.region(for: route, size: size)
        )
        let withMarkers = try #require(
            SummaryMapOverviewCamera.region(
                for: route + [route[0], route[2], route[2]],
                size: size
            )
        )

        #expect(routeOnly.center.latitude == withMarkers.center.latitude)
        #expect(routeOnly.center.longitude == withMarkers.center.longitude)
        #expect(
            routeOnly.span.latitudeDelta == withMarkers.span.latitudeDelta
        )
        #expect(
            routeOnly.span.longitudeDelta == withMarkers.span.longitudeDelta
        )
    }

    @Test("Globe framing uses the shortest dateline interval")
    func globeFramingAcrossDateline() throws {
        let region = try #require(SummaryMapOverviewCamera.region(
            for: [
                CLLocationCoordinate2D(latitude: 35, longitude: 170),
                CLLocationCoordinate2D(latitude: 40, longitude: -170),
            ],
            size: CGSize(width: 440, height: 290)
        ))

        #expect(region.span.longitudeDelta < 60)
        #expect(abs(abs(region.center.longitude) - 180) < 1)
    }

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

    @Test("A slot retains multiple content revisions for later reuse")
    func contentRevisionReuse() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = InvocationCounter()
        let store = SummaryMapSnapshotStore(
            directory: directory,
            renderer: { request in
                await counter.increment()
                return Data(request.contentHash.utf8)
            }
        )
        let oldRequest = request(slot: "day-2026-8-5", version: 1)
        let newRequest = request(slot: "day-2026-8-5", version: 2)

        _ = try await store.data(for: oldRequest)
        _ = try await store.data(for: newRequest)

        let reopened = SummaryMapSnapshotStore(
            directory: directory,
            renderer: { _ in
                await counter.increment()
                return Data("unexpected rerender".utf8)
            }
        )
        _ = try await reopened.data(for: oldRequest)
        _ = try await reopened.data(for: newRequest)

        let slot = directory.appending(
            path: newRequest.slotHash,
            directoryHint: .isDirectory
        )
        let contentDirectories = try FileManager.default.contentsOfDirectory(
            at: slot,
            includingPropertiesForKeys: nil
        )
        #expect(Set(contentDirectories.map(\.lastPathComponent)) == Set([
            oldRequest.contentHash,
            newRequest.contentHash,
        ]))
        let renderCount = await counter.value
        #expect(renderCount == 2)
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

    @Test("Cached-only prewarming never starts a render")
    func cachedOnlyPrewarming() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = InvocationCounter()
        let store = SummaryMapSnapshotStore(
            directory: directory,
            renderer: { _ in
                await counter.increment()
                return Data("unexpected render".utf8)
            }
        )

        await store.prewarm(
            [request(slot: "uncached", version: 1)],
            rendersMissingSnapshots: false
        )

        let renderCount = await counter.value
        #expect(renderCount == 0)
    }

    @Test("Cancelling the only reader cancels its render")
    func renderCancellation() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = InvocationCounter()
        let store = SummaryMapSnapshotStore(
            directory: directory,
            renderer: { _ in
                await counter.increment()
                try await Task.sleep(for: .seconds(30))
                return Data("late render".utf8)
            }
        )
        let request = request(slot: "cancelled", version: 1)
        let load = Task { try await store.data(for: request) }

        while await counter.value == 0 { await Task.yield() }
        load.cancel()
        await #expect(throws: CancellationError.self) {
            try await load.value
        }
        let cached = await store.cachedData(for: request)
        #expect(cached == nil)
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
