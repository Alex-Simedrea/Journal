//
//  SummaryMapSnapshotService.swift
//  Journal
//

import CryptoKit
import ImageIO
@preconcurrency import MapKit
import SwiftUI
import UniformTypeIdentifiers
import UIKit

nonisolated struct SummaryMapSnapshotRequest: Hashable, Sendable {
    enum Appearance: String, Codable, Hashable, Sendable {
        case light
        case dark
    }

    struct Variant: Codable, Hashable, Sendable {
        let pixelWidth: Int
        let pixelHeight: Int
        let scale: Double
        let appearance: Appearance

        var pointSize: CGSize {
            CGSize(
                width: Double(pixelWidth) / scale,
                height: Double(pixelHeight) / scale
            )
        }
    }

    let slotID: String
    let content: SummaryMapSnapshotContent
    let variant: Variant
    let slotHash: String
    let contentHash: String
    let variantHash: String
    let cacheKey: String

    init(
        slotID: String,
        content: SummaryMapSnapshotContent,
        variant: Variant
    ) {
        self.slotID = slotID
        self.content = content
        self.variant = variant
        let computedSlotHash = Self.digest(
            slotID.data(using: .utf8) ?? Data()
        )
        let computedContentHash = Self.digest(Self.encoded(content))
        let computedVariantHash = Self.digest(Self.encoded(variant))
        slotHash = computedSlotHash
        contentHash = computedContentHash
        variantHash = computedVariantHash
        cacheKey = [
            computedSlotHash,
            computedContentHash,
            computedVariantHash,
        ].joined(separator: "/")
    }

    private static func encoded<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)) ?? Data()
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated struct SummaryMapSnapshotContent: Codable, Hashable, Sendable {
    enum Camera: Codable, Hashable, Sendable {
        case overview
        case place(center: SummaryMapCoordinate, diameterMeters: Double)
    }

    let renderVersion: Int
    let camera: Camera
    let markers: [SummaryMapMarkerDescriptor]
    let paths: [SummaryMapPathDescriptor]
}

nonisolated struct SummaryMapCoordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    var mapCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

nonisolated struct SummaryMapColor: Codable, Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    func withAlpha(_ alpha: Double) -> SummaryMapColor {
        SummaryMapColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

nonisolated struct SummaryMapMarkerDescriptor: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let coordinate: SummaryMapCoordinate
    let systemImageName: String
    let color: SummaryMapColor
    let accuracyRadiusMeters: Double
    let radiusCenter: SummaryMapCoordinate?

    var displayCoordinate: CLLocationCoordinate2D {
        guard accuracyRadiusMeters > 0 else { return coordinate.mapCoordinate }
        return radiusCenter?.mapCoordinate ?? coordinate.mapCoordinate
    }
}

nonisolated struct SummaryMapPathDescriptor: Codable, Hashable, Sendable {
    struct Stroke: Codable, Hashable, Sendable {
        let color: SummaryMapColor
        let lineWidth: Double
    }

    let id: UUID
    let coordinates: [SummaryMapCoordinate]
    let strokes: [Stroke]
}

nonisolated enum SummaryMapOverviewCamera {
    private static let padding = 1.35

    static func region(
        for coordinates: [CLLocationCoordinate2D],
        size: CGSize
    ) -> MKCoordinateRegion? {
        let coordinates = uniqueCoordinates(coordinates)
        guard let first = coordinates.first else { return nil }
        guard coordinates.count > 1 else {
            return MKCoordinateRegion(
                center: first,
                latitudinalMeters: 1_200,
                longitudinalMeters: 1_200
            )
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudeInterval = minimalLongitudeInterval(
            coordinates.map(\.longitude)
        )
        let minimumLatitude = latitudes.min() ?? first.latitude
        let maximumLatitude = latitudes.max() ?? first.latitude
        let centerLatitude = (minimumLatitude + maximumLatitude) / 2
        let centerLongitude = normalizedLongitude(
            longitudeInterval.start + longitudeInterval.span / 2
        )

        var latitudeSpan = max(maximumLatitude - minimumLatitude, 0.5)
        var longitudeSpan = max(longitudeInterval.span, 0.5)
        let aspect = max(0.25, size.width / max(size.height, 1))
        let longitudeScale = max(0.2, cos(centerLatitude * .pi / 180))
        let displayedAspect = longitudeSpan * longitudeScale / latitudeSpan
        if displayedAspect > aspect {
            latitudeSpan = longitudeSpan * longitudeScale / aspect
        } else {
            longitudeSpan = latitudeSpan * aspect / longitudeScale
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: centerLatitude,
                longitude: centerLongitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: min(170, latitudeSpan * padding),
                longitudeDelta: min(350, longitudeSpan * padding)
            )
        )
    }

    private static func uniqueCoordinates(
        _ coordinates: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D] {
        struct CoordinateKey: Hashable {
            let latitude: Int64
            let longitude: Int64

            init(_ coordinate: CLLocationCoordinate2D) {
                latitude = Int64((coordinate.latitude * 1_000_000).rounded())
                longitude = Int64((coordinate.longitude * 1_000_000).rounded())
            }
        }

        var keys = Set<CoordinateKey>()
        return coordinates.filter { coordinate in
            keys.insert(CoordinateKey(coordinate)).inserted
        }
    }

    private static func minimalLongitudeInterval(
        _ longitudes: [CLLocationDegrees]
    ) -> (start: Double, span: Double) {
        let sorted = longitudes.map { longitude in
            let value = longitude.truncatingRemainder(dividingBy: 360)
            return value < 0 ? value + 360 : value
        }.sorted()
        guard sorted.count > 1 else { return (sorted.first ?? 0, 0) }

        var largestGap = -Double.infinity
        var intervalStart = sorted[0]
        for index in sorted.indices {
            let current = sorted[index]
            let next = index == sorted.index(before: sorted.endIndex)
                ? sorted[0] + 360
                : sorted[index + 1]
            let gap = next - current
            if gap > largestGap {
                largestGap = gap
                intervalStart = next.truncatingRemainder(dividingBy: 360)
            }
        }
        return (intervalStart, max(0, 360 - largestGap))
    }

    private static func normalizedLongitude(_ longitude: Double) -> Double {
        var value = longitude.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }
}

nonisolated enum SummaryMapVisibleRouteSelector {
    // A route shorter than twice the rendered stroke width reads as a dot at
    // this map scale and adds clutter without communicating a journey.
    private static let minimumFootprintPoints = 6.0

    static func paths(
        from paths: [TimelineMapPath],
        markers: [TimelineMapMarker],
        size: CGSize
    ) -> [TimelineMapPath] {
        guard !paths.isEmpty else { return [] }
        let framingCoordinates = markers.map(\.displayCoordinate)
            + paths.flatMap(\.coordinates)
        guard let region = SummaryMapOverviewCamera.region(
            for: framingCoordinates,
            size: size
        ) else { return paths }

        return paths.filter { path in
            visualFootprint(
                of: path.coordinates,
                in: region,
                size: size
            ) >= minimumFootprintPoints
        }
    }

    private static func visualFootprint(
        of coordinates: [CLLocationCoordinate2D],
        in region: MKCoordinateRegion,
        size: CGSize
    ) -> Double {
        guard coordinates.count > 1 else { return 0 }
        let latitudes = coordinates.map(\.latitude)
        let latitudeSpan = (latitudes.max() ?? 0) - (latitudes.min() ?? 0)
        let longitudeSpan = minimalLongitudeSpan(
            coordinates.map(\.longitude)
        )
        let width = longitudeSpan
            / max(region.span.longitudeDelta, .leastNonzeroMagnitude)
            * Double(size.width)
        let height = latitudeSpan
            / max(region.span.latitudeDelta, .leastNonzeroMagnitude)
            * Double(size.height)
        return hypot(width, height)
    }

    private static func minimalLongitudeSpan(
        _ longitudes: [CLLocationDegrees]
    ) -> Double {
        let sorted = longitudes.map { longitude in
            let value = longitude.truncatingRemainder(dividingBy: 360)
            return value < 0 ? value + 360 : value
        }.sorted()
        guard sorted.count > 1 else { return 0 }

        var largestGap = 0.0
        for index in sorted.indices {
            let next = index == sorted.index(before: sorted.endIndex)
                ? sorted[0] + 360
                : sorted[index + 1]
            largestGap = max(largestGap, next - sorted[index])
        }
        return max(0, 360 - largestGap)
    }
}

nonisolated enum SummaryMapSnapshotRequestFactory {
    private static let overviewRenderVersion = 35
    private static let placeRenderVersion = 28

    static func overview(
        slotID: String,
        data: TimelineOverviewData,
        size: CGSize,
        displayScale: CGFloat,
        appearance: SummaryMapSnapshotRequest.Appearance
    ) -> SummaryMapSnapshotRequest? {
        guard data.hasContent else { return nil }
        return request(
            slotID: slotID,
            data: data,
            camera: .overview,
            size: size,
            displayScale: displayScale,
            appearance: appearance
        )
    }

    static func place(
        slotID: String,
        location: TimelineLocationSnapshot,
        size: CGSize,
        displayScale: CGFloat,
        appearance: SummaryMapSnapshotRequest.Appearance
    ) -> SummaryMapSnapshotRequest? {
        guard location.hasCoordinate else { return nil }
        let marker = TimelineMapMarker(location: location)
        let center = location.radiusCenterCoordinate ?? location.coordinate
        let diameter = max(320, max(location.accuracyRadiusMeters, 0) * 2.6)
        return request(
            slotID: slotID,
            data: TimelineOverviewData(markers: [marker]),
            camera: .place(
                center: SummaryMapCoordinate(
                    latitude: center.latitude,
                    longitude: center.longitude
                ),
                diameterMeters: diameter
            ),
            size: size,
            displayScale: displayScale,
            appearance: appearance
        )
    }

    private static func request(
        slotID: String,
        data: TimelineOverviewData,
        camera: SummaryMapSnapshotContent.Camera,
        size: CGSize,
        displayScale: CGFloat,
        appearance: SummaryMapSnapshotRequest.Appearance
    ) -> SummaryMapSnapshotRequest? {
        let scale = max(displayScale, 1)
        let pixelWidth = evenPixelCount(size.width * scale)
        let pixelHeight = evenPixelCount(size.height * scale)
        guard pixelWidth > 1, pixelHeight > 1 else { return nil }

        let markers = data.markers.map { marker in
            SummaryMapMarkerDescriptor(
                id: marker.id,
                name: marker.name,
                coordinate: SummaryMapCoordinate(
                    latitude: marker.latitude,
                    longitude: marker.longitude
                ),
                systemImageName: marker.systemImage.rawValue,
                color: markerColor(
                    for: marker.systemImage,
                    appearance: appearance
                ),
                accuracyRadiusMeters: marker.accuracyRadiusMeters,
                radiusCenter: marker.radiusCenterCoordinate.map {
                    SummaryMapCoordinate(
                        latitude: $0.latitude,
                        longitude: $0.longitude
                    )
                }
            )
        }
        let visiblePaths: [TimelineMapPath]
        switch data.pathDisplayMode {
        case .all:
            visiblePaths = data.paths
        case .visibleAtMapScale:
            visiblePaths = SummaryMapVisibleRouteSelector.paths(
                from: data.paths,
                markers: data.markers,
                size: size
            )
        }
        let paths = visiblePaths.map { path in
            let strokes: [SummaryMapPathDescriptor.Stroke]
            switch path.kind {
            case .transit(let transitType):
                strokes = [
                    .init(
                        color: transitColor(for: transitType),
                        lineWidth: 3
                    ),
                ]
            case .workout:
                strokes = [
                    .init(
                        color: SummaryMapColor(
                            red: 0,
                            green: 0,
                            blue: 0,
                            alpha: 0.44
                        ),
                        lineWidth: 6
                    ),
                    .init(
                        color: SummaryMapColor(
                            red: 182 / 255,
                            green: 1,
                            blue: 0,
                            alpha: 1
                        ),
                        lineWidth: 3.5
                    ),
                ]
            }
            return SummaryMapPathDescriptor(
                id: path.id,
                coordinates: path.coordinates.map {
                    SummaryMapCoordinate(
                        latitude: $0.latitude,
                        longitude: $0.longitude
                    )
                },
                strokes: strokes
            )
        }
        let renderVersion: Int
        switch camera {
        case .overview:
            renderVersion = overviewRenderVersion
        case .place:
            renderVersion = placeRenderVersion
        }
        return SummaryMapSnapshotRequest(
            slotID: slotID,
            content: SummaryMapSnapshotContent(
                renderVersion: renderVersion,
                camera: camera,
                markers: markers,
                paths: paths
            ),
            variant: .init(
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                scale: Double(scale),
                appearance: appearance
            )
        )
    }

    private static func markerColor(
        for image: PlaceSystemImage,
        appearance: SummaryMapSnapshotRequest.Appearance
    ) -> SummaryMapColor {
        let light: UInt32
        let dark: UInt32
        switch image {
        case .mappin, .medical, .tram, .gasStation, .heart:
            (light, dark) = (0xFF3B30, 0xFF453A)
        case .house, .cart, .library, .computer, .airport, .car, .ferry,
             .parking, .people:
            (light, dark) = (0x007AFF, 0x0A84FF)
        case .buildings, .hotel, .school, .camera, .gaming:
            (light, dark) = (0x5856D6, 0x5E5CE6)
        case .civicBuilding, .cafe, .work, .pets:
            (light, dark) = (0xA2845E, 0xAC8E68)
        case .storefront, .dining, .running, .basketball, .camping, .ticket:
            (light, dark) = (0xFF9500, 0xFF9F0A)
        case .bag, .cake, .pharmacy:
            (light, dark) = (0xFF2D55, 0xFF375F)
        case .bar, .music, .theater:
            (light, dark) = (0xAF52DE, 0xBF5AF2)
        case .stethoscope:
            (light, dark) = (0x30B0C7, 0x40CBE0)
        case .walking, .sports, .soccer, .nature, .park, .cycling, .bus:
            (light, dark) = (0x34C759, 0x30D158)
        case .gym, .mountain:
            (light, dark) = (0x8E8E93, 0x8E8E93)
        case .beach, .water:
            (light, dark) = (0x32ADE6, 0x64D2FF)
        case .star:
            (light, dark) = (0xFFCC00, 0xFFD60A)
        }
        return color(hex: appearance == .dark ? dark : light)
    }

    private static func transitColor(for name: String) -> SummaryMapColor {
        let normalized = name
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hex: UInt32 = switch normalized {
        case "walk": 0x34C759
        case "bicycle": 0x00C7BE
        case "scooter": 0x32ADE6
        case "motorcycle": 0xFF9F0A
        case "car": 0x0A84FF
        case "taxi": 0xFFD60A
        case "ride share": 0x5E5CE6
        case "uber": 0x000000
        case "bolt": 0x34BB78
        case "lyft": 0xFF00BF
        case "bus": 0x30D158
        case "train": 0x2D59B3
        case "metro": 0xFF453A
        case "tram": 0xFF9F0A
        case "ferry": 0x64D2FF
        case "flight": 0x007AFF
        default: 0x6B7280
        }
        return color(hex: hex, alpha: 0.82)
    }

    private static func color(
        hex: UInt32,
        alpha: Double = 1
    ) -> SummaryMapColor {
        SummaryMapColor(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            alpha: alpha
        )
    }

    private static func evenPixelCount(_ value: CGFloat) -> Int {
        let rounded = Int(value.rounded())
        return rounded.isMultiple(of: 2) ? rounded : rounded + 1
    }
}

nonisolated enum SummaryMapSnapshotRequestInput: Sendable {
    case overview(
        slotID: String,
        data: TimelineOverviewData,
        size: CGSize
    )
    case place(
        slotID: String,
        location: TimelineLocationSnapshot,
        size: CGSize
    )

    func request(
        displayScale: CGFloat,
        appearance: SummaryMapSnapshotRequest.Appearance
    ) -> SummaryMapSnapshotRequest? {
        switch self {
        case .overview(let slotID, let data, let size):
            SummaryMapSnapshotRequestFactory.overview(
                slotID: slotID,
                data: data,
                size: size,
                displayScale: displayScale,
                appearance: appearance
            )
        case .place(let slotID, let location, let size):
            SummaryMapSnapshotRequestFactory.place(
                slotID: slotID,
                location: location,
                size: size,
                displayScale: displayScale,
                appearance: appearance
            )
        }
    }
}

nonisolated enum SummaryMapSnapshotRequestBuilder {
    static func request(
        for input: SummaryMapSnapshotRequestInput,
        displayScale: CGFloat,
        appearance: SummaryMapSnapshotRequest.Appearance
    ) async -> SummaryMapSnapshotRequest? {
        await Task.detached(priority: .utility) {
            input.request(
                displayScale: displayScale,
                appearance: appearance
            )
        }.value
    }

    static func requests(
        for inputs: [SummaryMapSnapshotRequestInput],
        displayScale: CGFloat,
        appearance: SummaryMapSnapshotRequest.Appearance
    ) async -> [SummaryMapSnapshotRequest] {
        await Task.detached(priority: .utility) {
            inputs.compactMap {
                $0.request(
                    displayScale: displayScale,
                    appearance: appearance
                )
            }
        }.value
    }
}

actor SummaryMapSnapshotStore {
    typealias Renderer = @Sendable (SummaryMapSnapshotRequest) async throws -> Data

    nonisolated static let shared = SummaryMapSnapshotStore()
    nonisolated static let byteLimit = 200 * 1_024 * 1_024

    private static let cacheDirectoryName = "SummaryMapSnapshots-v4"
    private static let legacyCacheDirectoryNames = [
        "SummaryMapSnapshots",
        "SummaryMapSnapshots-v2",
        "SummaryMapSnapshots-v3",
    ]

    private struct InFlight {
        let id: UUID
        let task: Task<Data, any Error>
        var waiterCount: Int
    }

    private struct MemoryEntry {
        let data: Data
        let appearance: SummaryMapSnapshotRequest.Appearance
        var access: UInt64
    }

    private let directory: URL
    private let maximumBytes: Int
    private let renderer: Renderer
    private var inFlight: [String: InFlight] = [:]
    private var memory: [String: MemoryEntry] = [:]
    private var memoryBytes = 0
    private var memoryClock: UInt64 = 0
    private let memoryLimit = 32 * 1_024 * 1_024

    init(
        directory: URL? = nil,
        maximumBytes: Int = SummaryMapSnapshotStore.byteLimit,
        renderer: @escaping Renderer = { request in
            try await SummaryMapSnapshotRenderer.render(request)
        }
    ) {
        let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        if let directory {
            self.directory = directory
        } else {
            self.directory = caches.appending(
                path: Self.cacheDirectoryName,
                directoryHint: .isDirectory
            )
            for legacyName in Self.legacyCacheDirectoryNames {
                let legacyDirectory = caches.appending(
                    path: legacyName,
                    directoryHint: .isDirectory
                )
                try? FileManager.default.removeItem(at: legacyDirectory)
            }
        }
        self.maximumBytes = maximumBytes
        self.renderer = renderer
    }

    func data(for request: SummaryMapSnapshotRequest) async throws -> Data {
        let key = request.cacheKey
        if let cached = cachedData(for: request) { return cached }

        if var existing = inFlight[key] {
            existing.waiterCount += 1
            inFlight[key] = existing
            return try await renderedData(
                for: request,
                key: key,
                inFlight: existing
            )
        }

        let token = UUID()
        let renderer = renderer
        let task = Task<Data, any Error>(priority: .utility) {
            try await SummaryMapRenderLimiter.shared.perform {
                try await renderer(request)
            }
        }
        let pending = InFlight(id: token, task: task, waiterCount: 1)
        inFlight[key] = pending

        return try await renderedData(
            for: request,
            key: key,
            inFlight: pending
        )
    }

    private func renderedData(
        for request: SummaryMapSnapshotRequest,
        key: String,
        inFlight pending: InFlight
    ) async throws -> Data {
        do {
            let data = try await withTaskCancellationHandler {
                try await pending.task.value
            } onCancel: {
                Task {
                    await self.cancelWaiter(
                        forKey: key,
                        token: pending.id
                    )
                }
            }
            try Task.checkCancellation()
            if inFlight[key]?.id == pending.id {
                try prepareDirectory(for: request)
                let fileURL = fileURL(for: request)
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: fileURL, options: .atomic)
                remember(
                    data,
                    forKey: key,
                    appearance: request.variant.appearance
                )
                inFlight[key] = nil
                try trimContentRevisions(for: request)
                try trimDiskIfNeeded()
            }
            return data
        } catch {
            if !Task.isCancelled,
               inFlight[key]?.id == pending.id {
                inFlight[key] = nil
            }
            throw error
        }
    }

    private func cancelWaiter(forKey key: String, token: UUID) {
        guard var pending = inFlight[key], pending.id == token else {
            return
        }
        pending.waiterCount -= 1
        if pending.waiterCount <= 0 {
            inFlight[key] = nil
            pending.task.cancel()
        } else {
            inFlight[key] = pending
        }
    }

    func cachedData(for request: SummaryMapSnapshotRequest) -> Data? {
        let key = request.cacheKey
        if var entry = memory[key] {
            memoryClock &+= 1
            entry.access = memoryClock
            memory[key] = entry
            return entry.data
        }

        let fileURL = fileURL(for: request)
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return nil
        }
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )
        remember(
            data,
            forKey: key,
            appearance: request.variant.appearance
        )
        return data
    }

    func prewarm(
        _ requests: [SummaryMapSnapshotRequest],
        retainDecodedImages: Bool = false,
        rendersMissingSnapshots: Bool = true
    ) async {
        for request in requests {
            guard !Task.isCancelled else { return }
            let snapshotData: Data?
            if rendersMissingSnapshots {
                snapshotData = try? await data(for: request)
            } else {
                snapshotData = cachedData(for: request)
            }
            guard let snapshotData else { continue }
            if retainDecodedImages {
                _ = await SummaryMapDecodedImageCache.image(
                    data: snapshotData,
                    for: request
                )
            }
        }
    }

    private func prepareDirectory(for request: SummaryMapSnapshotRequest) throws {
        let fileManager = FileManager.default
        let slotDirectory = directory.appending(
            path: request.slotHash,
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: slotDirectory,
            withIntermediateDirectories: true
        )
        let contentDirectory = slotDirectory.appending(
            path: request.contentHash,
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: contentDirectory,
            withIntermediateDirectories: true
        )
    }

    private func fileURL(for request: SummaryMapSnapshotRequest) -> URL {
        directory
            .appending(path: request.slotHash, directoryHint: .isDirectory)
            .appending(path: request.contentHash, directoryHint: .isDirectory)
            .appending(
                path: "\(request.variant.appearance.rawValue)-\(request.variantHash)"
            )
            .appendingPathExtension("heic")
    }

    private func trimContentRevisions(
        for request: SummaryMapSnapshotRequest
    ) throws {
        let slotDirectory = directory.appending(
            path: request.slotHash,
            directoryHint: .isDirectory
        )
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        let revisions = try FileManager.default.contentsOfDirectory(
            at: slotDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).filter { url in
            let values = try? url.resourceValues(forKeys: keys)
            return values?.isDirectory == true
        }
        let appearancePrefix = "\(request.variant.appearance.rawValue)-"

        for revision in revisions where
            revision.lastPathComponent != request.contentHash {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: revision,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for file in files where file.lastPathComponent.hasPrefix(
                appearancePrefix
            ) {
                try? FileManager.default.removeItem(at: file)
            }

            let keyPrefix = "\(request.slotHash)/\(revision.lastPathComponent)/"
            let obsoleteKeys = memory.filter { key, entry in
                key.hasPrefix(keyPrefix)
                    && entry.appearance == request.variant.appearance
            }.map(\.key)
            for key in obsoleteKeys {
                if let entry = memory.removeValue(forKey: key) {
                    memoryBytes -= entry.data.count
                }
            }

            let remainingFiles = try? FileManager.default.contentsOfDirectory(
                at: revision,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            if remainingFiles?.isEmpty == true {
                try? FileManager.default.removeItem(at: revision)
            }
        }
    }

    private func remember(
        _ data: Data,
        forKey key: String,
        appearance: SummaryMapSnapshotRequest.Appearance
    ) {
        memoryClock &+= 1
        if let old = memory[key] { memoryBytes -= old.data.count }
        memory[key] = MemoryEntry(
            data: data,
            appearance: appearance,
            access: memoryClock
        )
        memoryBytes += data.count
        while memoryBytes > memoryLimit,
              let oldest = memory.min(by: { $0.value.access < $1.value.access }) {
            memoryBytes -= oldest.value.data.count
            memory[oldest.key] = nil
        }
    }

    private func trimDiskIfNeeded() throws {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }

        var files: [(url: URL, size: Int, date: Date)] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { continue }
            files.append((
                url,
                values?.fileSize ?? 0,
                values?.contentModificationDate ?? .distantPast
            ))
        }
        var total = files.reduce(0) { $0 + $1.size }
        guard total > maximumBytes else { return }
        for file in files.sorted(by: { $0.date < $1.date }) {
            try? FileManager.default.removeItem(at: file.url)
            total -= file.size
            if total <= maximumBytes { break }
        }
    }
}

nonisolated enum SummaryMapDecodedImageCache {
    private final class Storage: @unchecked Sendable {
        let images = NSCache<NSString, UIImage>()

        init() {
            images.countLimit = 96
            images.totalCostLimit = 64 * 1_024 * 1_024
        }
    }

    private static let storage = Storage()

    static func cachedImage(
        for request: SummaryMapSnapshotRequest
    ) -> UIImage? {
        storage.images.object(forKey: key(for: request) as NSString)
    }

    static func image(
        data: Data,
        for request: SummaryMapSnapshotRequest
    ) async -> UIImage? {
        if let cached = cachedImage(for: request) { return cached }
        guard let encoded = UIImage(
            data: data,
            scale: CGFloat(request.variant.scale)
        ) else { return nil }
        // Map snapshots are already rendered at their final pixel size.
        // Preparing, rather than resizing, moves JPEG decompression away
        // from SwiftUI's frame commit and leaves a display-ready backing.
        let decoded = await encoded.byPreparingForDisplay() ?? encoded
        guard !Task.isCancelled else { return nil }
        storage.images.setObject(
            decoded,
            forKey: key(for: request) as NSString,
            cost: request.variant.pixelWidth
                * request.variant.pixelHeight * 4
        )
        return decoded
    }

    private static func key(for request: SummaryMapSnapshotRequest) -> String {
        "summary-map/\(request.cacheKey)"
    }
}

private actor SummaryMapRenderLimiter {
    // Every timeline snapshot now relies on MKMapView so MapKit owns marker
    // collision, z-order, shadows, and globe projection. Keep only one native
    // map render active to avoid compounding its unavoidable main-thread work.
    static let shared = SummaryMapRenderLimiter(limit: 1)

    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        available = max(limit, 1)
    }

    func perform<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        await acquire()
        do {
            let value = try await operation()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

nonisolated enum SummaryMapSnapshotRenderer {
    static func render(_ request: SummaryMapSnapshotRequest) async throws -> Data {
        let image: CGImage
        switch request.content.camera {
        case .overview:
            image = try await SummaryMapViewRenderer.render(request)
        case .place:
            image = try await SummaryMapViewRenderer.render(request)
        }
        try Task.checkCancellation()
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.90] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data as Data
    }
}

nonisolated private enum SummaryMapSnapshotterRenderer {
    static func requiresNativeProjection(
        _ request: SummaryMapSnapshotRequest
    ) -> Bool {
        JournalMapDisplayStylePolicy.usesHybridStyle(
            for: cameraCoordinates(in: request)
        )
    }

    static func render(_ request: SummaryMapSnapshotRequest) async throws -> CGImage {
        let options = MKMapSnapshotter.Options()
        options.size = request.variant.pointSize
        options.traitCollection = UITraitCollection { traits in
            traits.displayScale = request.variant.scale
            traits.userInterfaceStyle = request.variant.appearance == .dark
                ? .dark
                : .light
        }
        options.preferredConfiguration = MKStandardMapConfiguration(
            elevationStyle: .flat
        )
        applyCamera(
            to: options,
            request: request,
            usesHybridStyle: false
        )

        let snapshot = try await MKMapSnapshotter(options: options).start()
        try Task.checkCancellation()
        return try composite(snapshot: snapshot, request: request)
    }

    private static func cameraCoordinates(
        in request: SummaryMapSnapshotRequest
    ) -> [CLLocationCoordinate2D] {
        request.content.paths.flatMap { path -> [CLLocationCoordinate2D] in
            guard let first = path.coordinates.first?.mapCoordinate,
                  let last = path.coordinates.last?.mapCoordinate else {
                return []
            }
            return [first, last]
        } + request.content.markers.map(\.displayCoordinate)
    }

    private static func allCoordinates(
        in request: SummaryMapSnapshotRequest
    ) -> [CLLocationCoordinate2D] {
        request.content.paths.flatMap {
            $0.coordinates.map(\.mapCoordinate)
        } + request.content.markers.map(\.displayCoordinate)
    }

    private static func applyCamera(
        to options: MKMapSnapshotter.Options,
        request: SummaryMapSnapshotRequest,
        usesHybridStyle: Bool
    ) {
        let coordinates = usesHybridStyle
            ? cameraCoordinates(in: request)
            : allCoordinates(in: request)
        guard coordinates.count > 1 else {
            if let coordinate = coordinates.first {
                options.region = MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 1_200,
                    longitudinalMeters: 1_200
                )
            }
            return
        }

        if usesHybridStyle,
           var region = SummaryMapOverviewCamera.region(
               for: coordinates,
               size: request.variant.pointSize
           ) {
            region.span.latitudeDelta = min(
                170,
                region.span.latitudeDelta * 2.2
            )
            region.span.longitudeDelta = min(
                350,
                region.span.longitudeDelta * 2.2
            )
            options.region = region
            return
        }

        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(
                origin: point,
                size: MKMapSize(width: 1, height: 1)
            ))
        }
        guard !rect.isNull else { return }
        let size = request.variant.pointSize
        let horizontalFraction = max(
            0.1,
            1 - 2 * max(18, size.width * 0.12) / max(size.width, 1)
        )
        let verticalFraction = max(
            0.1,
            1 - 2 * max(18, size.height * 0.12) / max(size.height, 1)
        )
        let targetWidth = max(rect.width, 1) / horizontalFraction
        let targetHeight = max(rect.height, 1) / verticalFraction
        options.mapRect = MKMapRect(
            x: rect.midX - targetWidth / 2,
            y: rect.midY - targetHeight / 2,
            width: targetWidth,
            height: targetHeight
        )
    }

    private static func composite(
        snapshot: MKMapSnapshotter.Snapshot,
        request: SummaryMapSnapshotRequest
    ) throws -> CGImage {
        let format = UIGraphicsImageRendererFormat(for: snapshot.traitCollection)
        format.scale = request.variant.scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: request.variant.pointSize,
            format: format
        ).image { context in
            snapshot.image.draw(at: .zero)
            drawPaths(
                request.content.paths,
                snapshot: snapshot,
                in: context.cgContext
            )
        }
        guard let result = image.cgImage else {
            throw CocoaError(.coderInvalidValue)
        }
        return result
    }

    private static func drawPaths(
        _ paths: [SummaryMapPathDescriptor],
        snapshot: MKMapSnapshotter.Snapshot,
        in context: CGContext
    ) {
        context.saveGState()
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        for path in paths where path.coordinates.count > 1 {
            let points = path.coordinates.map {
                snapshot.point(for: $0.mapCoordinate)
            }
            guard let first = points.first,
                  points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
                continue
            }
            let route = CGMutablePath()
            route.move(to: first)
            for point in points.dropFirst() { route.addLine(to: point) }
            for stroke in path.strokes {
                context.addPath(route)
                context.setStrokeColor(stroke.color.cgColor)
                context.setLineWidth(stroke.lineWidth)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.strokePath()
            }
        }
        context.restoreGState()
    }

}

@MainActor
private enum SummaryMapViewRenderer {
    static func render(_ request: SummaryMapSnapshotRequest) async throws -> CGImage {
        try await SummaryMapRenderSession(request: request).render()
    }
}

@MainActor
private final class SummaryMapRenderSession: NSObject, MKMapViewDelegate {
    private static let markerReuseIdentifier = "summary-map-marker"

    private final class Annotation: MKPointAnnotation {
        let systemImageName: String
        let color: UIColor

        init(marker: SummaryMapMarkerDescriptor) {
            systemImageName = marker.systemImageName
            color = marker.color.uiColor
            super.init()
            coordinate = marker.displayCoordinate
            title = marker.name
        }
    }

    private enum OverlayStyle {
        case line(SummaryMapPathDescriptor.Stroke)
        case accuracy(SummaryMapColor)
    }

    private let request: SummaryMapSnapshotRequest
    private let mapView: MKMapView
    private let usesHybridStyle: Bool
    private var markerAnnotations: [Annotation] = []
    private var hostWindow: UIWindow?
    private var overlayStyles: [ObjectIdentifier: OverlayStyle] = [:]
    private var continuation: CheckedContinuation<CGImage, any Error>?
    private var timeoutTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var mapIsFullyRendered = false
    private var didFinish = false

    private var allOverviewCoordinates: [CLLocationCoordinate2D] {
        request.content.paths.flatMap {
            $0.coordinates.map(\.mapCoordinate)
        } + request.content.markers.map(\.displayCoordinate)
    }

    private var cameraCoordinates: [CLLocationCoordinate2D] {
        request.content.paths.flatMap { path -> [CLLocationCoordinate2D] in
            guard let first = path.coordinates.first?.mapCoordinate,
                  let last = path.coordinates.last?.mapCoordinate else {
                return []
            }
            return [first, last]
        } + request.content.markers.map(\.displayCoordinate)
    }

    private var edgeBleed: CGFloat {
        1 / max(request.variant.scale, 1)
    }

    private var renderingSize: CGSize {
        CGSize(
            width: request.variant.pointSize.width + edgeBleed * 2,
            height: request.variant.pointSize.height + edgeBleed * 2
        )
    }

    private var captureOffset: CGPoint {
        CGPoint(
            x: edgeBleed,
            y: edgeBleed
        )
    }

    private var usesPlaceCamera: Bool {
        if case .place = request.content.camera { true } else { false }
    }

    init(request: SummaryMapSnapshotRequest) {
        self.request = request
        let styleCoordinates = request.content.paths.flatMap {
            path -> [CLLocationCoordinate2D] in
            guard let first = path.coordinates.first?.mapCoordinate,
                  let last = path.coordinates.last?.mapCoordinate else {
                return []
            }
            return [first, last]
        } + request.content.markers.map(\.displayCoordinate)
        usesHybridStyle = JournalMapDisplayStylePolicy.usesHybridStyle(
            for: styleCoordinates
        )
        let edgeBleed = 1 / max(request.variant.scale, 1)
        let pointSize = request.variant.pointSize
        mapView = MKMapView(
            frame: CGRect(
                origin: .zero,
                size: CGSize(
                    width: pointSize.width + edgeBleed * 2,
                    height: pointSize.height + edgeBleed * 2
                )
            )
        )
        super.init()
    }

    func render() async throws -> CGImage {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                configureMap()
                timeoutTask = Task { [self] in
                    try? await Task.sleep(
                        for: usesHybridStyle ? .seconds(3) : .seconds(20)
                    )
                    guard !Task.isCancelled else { return }
                    if usesHybridStyle, hostWindow != nil {
                        prepareMarkerViewsForCapture()
                        finishRendering()
                    } else {
                        failRendering(with: URLError(.timedOut))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.failRendering(with: CancellationError())
            }
        }
    }

    func mapViewDidFinishRenderingMap(
        _ mapView: MKMapView,
        fullyRendered: Bool
    ) {
        guard fullyRendered else { return }
        mapIsFullyRendered = true
        scheduleFinishIfReady()
    }

    func mapView(
        _ mapView: MKMapView,
        viewFor annotation: any MKAnnotation
    ) -> MKAnnotationView? {
        guard let annotation = annotation as? Annotation else { return nil }
        guard let view = mapView.dequeueReusableAnnotationView(
            withIdentifier: Self.markerReuseIdentifier,
            for: annotation
        ) as? MKMarkerAnnotationView else { return nil }
        configure(view, for: annotation)
        return view
    }

    func mapView(
        _ mapView: MKMapView,
        didAdd views: [MKAnnotationView]
    ) {
        for case let view as MKMarkerAnnotationView in views {
            guard let annotation = view.annotation as? Annotation else {
                continue
            }
            // prepareForDisplay runs after viewFor and can restore MapKit's
            // adaptive marker policy. Reapply our settings once the prepared
            // view is installed in either map size.
            configure(view, for: annotation)
        }
        scheduleFinishIfReady()
    }

    private func configure(
        _ view: MKMarkerAnnotationView,
        for annotation: Annotation
    ) {
        view.animatesWhenAdded = false
        view.markerTintColor = annotation.color
        view.glyphTintColor = .white
        view.glyphText = nil
        view.glyphImage = UIImage(systemName: annotation.systemImageName)
        view.displayPriority = .defaultLow
        view.clusteringIdentifier = nil
        view.titleVisibility = switch request.content.camera {
        case .place: .visible
        case .overview: .hidden
        }
        view.subtitleVisibility = .hidden
    }

    private func scheduleFinishIfReady() {
        guard mapIsFullyRendered,
              finishTask == nil,
              markerAnnotations.allSatisfy({ annotation in
                  if usesHybridStyle,
                     !isProjectedOnScreen(annotation.coordinate) {
                      return true
                  }
                  return mapView.view(for: annotation)?.window != nil
              }) else { return }

        // Overview titles are intentionally hidden, so the installed marker
        // views and the fully-rendered map callback are sufficient readiness
        // signals for the cached capture.
        finishTask = Task { @MainActor [weak self] in
            if self?.usesHybridStyle == true {
                // Hybrid tiles can report fully rendered before MapKit's
                // attribution and globe projection complete their layout.
                try? await Task.sleep(for: .milliseconds(120))
            } else if self?.usesPlaceCamera == true {
                // SwiftUI's Marker waits for MapKit's deferred annotation
                // layout. A fully-rendered tile callback does not guarantee
                // that the native marker title has completed that pass.
                await self?.waitForNativePlaceTitles()
            } else {
                await Task.yield()
            }
            guard let self, !Task.isCancelled else { return }
            prepareMarkerViewsForCapture()
            finishRendering()
        }
    }

    private func isProjectedOnScreen(
        _ coordinate: CLLocationCoordinate2D
    ) -> Bool {
        let point = mapView.convert(coordinate, toPointTo: mapView)
        guard point.x.isFinite, point.y.isFinite else { return false }
        return mapView.bounds.insetBy(dx: -40, dy: -40).contains(point)
    }

    private func prepareMarkerViewsForCapture() {
        for annotation in markerAnnotations {
            guard let view = mapView.view(for: annotation)
                as? MKMarkerAnnotationView else { continue }
            configure(view, for: annotation)
            view.setNeedsLayout()
            view.setNeedsDisplay()
            view.layoutIfNeeded()
        }
        mapView.setNeedsLayout()
        mapView.setNeedsDisplay()
        mapView.layoutIfNeeded()
        CATransaction.flush()
    }

    private func waitForNativePlaceTitles() async {
        // Under load, MKMarkerAnnotationView can install its title several
        // display passes after the map tiles and marker balloon. Poll the
        // native view hierarchy rather than caching whichever pass happens
        // to land after a fixed delay.
        for _ in 0..<20 {
            guard !Task.isCancelled else { return }
            prepareMarkerViewsForCapture()
            if nativePlaceTitlesAreVisible { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private var nativePlaceTitlesAreVisible: Bool {
        request.content.markers.allSatisfy { marker in
            hierarchy(mapView, containsVisibleText: marker.name)
                || layerHierarchy(
                    mapView.layer,
                    containsVisibleText: marker.name
                )
        }
    }

    private func hierarchy(
        _ view: UIView,
        containsVisibleText text: String
    ) -> Bool {
        if let label = view as? UILabel,
           label.text == text,
           !label.isHidden,
           label.alpha > 0.01,
           label.bounds.width > 0,
           label.bounds.height > 0 {
            return true
        }
        return view.subviews.contains {
            hierarchy($0, containsVisibleText: text)
        }
    }

    private func layerHierarchy(
        _ layer: CALayer,
        containsVisibleText text: String
    ) -> Bool {
        if let textLayer = layer as? CATextLayer,
           renderedText(in: textLayer) == text,
           !textLayer.isHidden,
           textLayer.opacity > 0.01,
           textLayer.bounds.width > 0,
           textLayer.bounds.height > 0 {
            return true
        }
        return layer.sublayers?.contains {
            layerHierarchy($0, containsVisibleText: text)
        } ?? false
    }

    private func renderedText(in layer: CATextLayer) -> String? {
        switch layer.string {
        case let value as String: value
        case let value as NSAttributedString: value.string
        default: nil
        }
    }

    func mapView(
        _ mapView: MKMapView,
        rendererFor overlay: any MKOverlay
    ) -> MKOverlayRenderer {
        switch overlayStyles[ObjectIdentifier(overlay)] {
        case .line(let style):
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = style.color.uiColor
            renderer.lineWidth = style.lineWidth
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        case .accuracy(let color):
            let renderer = MKCircleRenderer(overlay: overlay)
            renderer.fillColor = color.uiColor.withAlphaComponent(0.14)
            renderer.strokeColor = color.uiColor.withAlphaComponent(0.62)
            renderer.lineWidth = 1.5
            return renderer
        case nil:
            return MKOverlayRenderer(overlay: overlay)
        }
    }

    private func configureMap() {
        mapView.delegate = self
        if usesHybridStyle {
            mapView.preferredConfiguration = MKHybridMapConfiguration(
                elevationStyle: .realistic
            )
        } else {
            mapView.preferredConfiguration = MKStandardMapConfiguration(
                elevationStyle: .flat
            )
        }
        mapView.overrideUserInterfaceStyle = request.variant.appearance == .dark
            ? .dark
            : .light
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsUserLocation = false
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: Self.markerReuseIdentifier
        )
        markerAnnotations = request.content.markers.map(Annotation.init(marker:))
        mapView.addAnnotations(markerAnnotations)
        addOverlays()
        applyCamera()
        // Configure the complete map before attaching it to a window. An
        // attached MKMapView may immediately report a finished render for its
        // initial empty state, which would otherwise cache a markerless image.
        attachToRenderingWindow()
        mapView.setNeedsLayout()
        mapView.layoutIfNeeded()
    }

    private func attachToRenderingWindow() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState != .unattached }) else {
            return
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: renderingSize)
        window.windowLevel = UIWindow.Level(rawValue: -1_000)
        window.isUserInteractionEnabled = false
        window.alpha = 0.01

        let controller = UIViewController()
        controller.view.frame = window.bounds
        controller.view.backgroundColor = .clear
        mapView.frame = controller.view.bounds
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(mapView)
        window.rootViewController = controller
        window.isHidden = false
        hostWindow = window
    }

    private func addOverlays() {
        for path in request.content.paths where path.coordinates.count > 1 {
            let coordinates = path.coordinates.map(\.mapCoordinate)
            for stroke in path.strokes {
                let overlay = MKPolyline(
                    coordinates: coordinates,
                    count: coordinates.count
                )
                overlayStyles[ObjectIdentifier(overlay)] = .line(stroke)
                mapView.addOverlay(overlay)
            }
        }
        for marker in request.content.markers
        where marker.accuracyRadiusMeters > 0 {
            let overlay = MKCircle(
                center: marker.displayCoordinate,
                radius: marker.accuracyRadiusMeters
            )
            overlayStyles[ObjectIdentifier(overlay)] = .accuracy(marker.color)
            mapView.addOverlay(overlay)
        }
    }

    private func applyCamera() {
        switch request.content.camera {
        case .place(let center, let diameterMeters):
            mapView.setRegion(
                MKCoordinateRegion(
                    center: center.mapCoordinate,
                    latitudinalMeters: diameterMeters,
                    longitudinalMeters: diameterMeters
                ),
                animated: false
            )
        case .overview:
            let coordinates = usesHybridStyle
                ? cameraCoordinates
                : allOverviewCoordinates
            guard coordinates.count > 1 else {
                if let coordinate = coordinates.first {
                    mapView.setRegion(
                        MKCoordinateRegion(
                            center: coordinate,
                            latitudinalMeters: 1_200,
                            longitudinalMeters: 1_200
                        ),
                        animated: false
                    )
                }
                return
            }
            if usesHybridStyle {
                if let region = SummaryMapOverviewCamera.region(
                    for: coordinates,
                    size: request.variant.pointSize
                ) {
                    mapView.setRegion(region, animated: false)
                    let fittedCamera = mapView.camera
                    mapView.setCamera(
                        MKMapCamera(
                            lookingAtCenter: fittedCamera.centerCoordinate,
                            fromDistance: fittedCamera
                                .centerCoordinateDistance * 2.2,
                            pitch: 0,
                            heading: fittedCamera.heading
                        ),
                        animated: false
                    )
                }
                return
            }
            var rect = MKMapRect.null
            for coordinate in coordinates {
                let point = MKMapPoint(coordinate)
                rect = rect.union(MKMapRect(
                    origin: point,
                    size: MKMapSize(width: 1, height: 1)
                ))
            }
            mapView.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(
                    top: max(18, renderingSize.height * 0.12),
                    left: max(18, renderingSize.width * 0.12),
                    bottom: max(18, renderingSize.height * 0.12),
                    right: max(18, renderingSize.width * 0.12)
                ),
                animated: false
            )
        }
    }

    private func finishRendering() {
        guard !didFinish, let continuation else { return }
        didFinish = true
        timeoutTask?.cancel()
        finishTask?.cancel()
        mapView.setNeedsLayout()
        mapView.layoutIfNeeded()
        let traits = UITraitCollection { traits in
            traits.displayScale = request.variant.scale
            traits.userInterfaceStyle = request.variant.appearance == .dark
                ? .dark
                : .light
        }
        let format = UIGraphicsImageRendererFormat(for: traits)
        format.scale = request.variant.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: request.variant.pointSize,
            format: format
        )
        let image = renderer.image { context in
            context.cgContext.translateBy(
                x: -captureOffset.x,
                y: -captureOffset.y
            )
            if !mapView.drawHierarchy(
                in: mapView.bounds,
                afterScreenUpdates: true
            ) {
                mapView.layer.render(in: context.cgContext)
            }
        }
        mapView.delegate = nil
        hostWindow?.isHidden = true
        hostWindow?.rootViewController = nil
        hostWindow = nil
        self.continuation = nil
        guard let image = image.cgImage else {
            continuation.resume(throwing: CocoaError(.coderInvalidValue))
            return
        }
        continuation.resume(returning: image)
    }

    private func failRendering(with error: any Error) {
        guard !didFinish, let continuation else { return }
        didFinish = true
        timeoutTask?.cancel()
        finishTask?.cancel()
        mapView.delegate = nil
        hostWindow?.isHidden = true
        hostWindow?.rootViewController = nil
        hostWindow = nil
        self.continuation = nil
        continuation.resume(throwing: error)
    }
}

@MainActor
extension HomeFeedModel {
    func prewarmMapSnapshots(
        contentWidth: CGFloat,
        displayScale: CGFloat,
        appearance: SummaryMapSnapshotRequest.Appearance
    ) async {
        guard contentWidth > 1 else { return }

        let newestFirst = Array(rows.reversed())
        let retainedDayCount = min(newestFirst.count, 12)
        let recentPhotos = newestFirst.prefix(retainedDayCount).flatMap {
            $0.summary.photos.prefix(4)
        }
        async let recentPhotoPrewarm: Void = SummaryPhotoThumbnailService.prewarm(
            recentPhotos
        )

        // Keep the immediately browsable window decoded. Older snapshots stay
        // on disk and are decoded on demand; eagerly decoding the whole journal
        // makes the first scroll interaction contend with MapKit and Photos.
        for row in newestFirst.prefix(retainedDayCount) {
            guard !Task.isCancelled else { return }
            await row.loadMapEnrichment()
            let inputs = daySnapshotRequestInputs(
                for: row,
                contentWidth: contentWidth
            )
            let requests = await SummaryMapSnapshotRequestBuilder.requests(
                for: inputs,
                displayScale: displayScale,
                appearance: appearance
            )
            await SummaryMapSnapshotStore.shared.prewarm(
                requests,
                retainDecodedImages: true,
                rendersMissingSnapshots: true
            )
        }

        await loadPeriodPhotoMetadata()
        let retainedPeriods = Array(monthRows.suffix(12))
            + Array(yearRows.suffix(3))
        let periodPhotos = retainedPeriods.flatMap {
            $0.summary.photos.prefix(4)
        }
        async let periodPhotoPrewarm: Void = SummaryPhotoThumbnailService
            .prewarm(periodPhotos)
        for row in retainedPeriods.reversed() {
            guard !Task.isCancelled else { return }
            await row.loadEnrichment()
            let inputs = periodSnapshotRequestInputs(
                for: row,
                contentWidth: contentWidth
            )
            let requests = await SummaryMapSnapshotRequestBuilder.requests(
                for: inputs,
                displayScale: displayScale,
                appearance: appearance
            )
            await SummaryMapSnapshotStore.shared.prewarm(
                requests,
                retainDecodedImages: true,
                rendersMissingSnapshots: true
            )
        }
        await recentPhotoPrewarm
        await periodPhotoPrewarm
    }

    private func daySnapshotRequestInputs(
        for row: DaySummaryRowModel,
        contentWidth: CGFloat
    ) -> [SummaryMapSnapshotRequestInput] {
        let recipe = DaySummaryLayoutRecipe.make(for: row.summary)
        guard let placement = recipe.placements.first(where: {
            $0.tile == .overview
        }) else { return [] }
        return [.overview(
            slotID: "day-\(row.id.id)-overview",
            data: row.overviewData,
            size: size(for: placement.frame, contentWidth: contentWidth)
        )]
    }

    private func periodSnapshotRequestInputs(
        for row: PeriodSummaryRowModel,
        contentWidth: CGFloat
    ) -> [SummaryMapSnapshotRequestInput] {
        let recipe = row.layoutRecipe
        var inputs: [SummaryMapSnapshotRequestInput] = []

        if let placement = recipe.placements.first(where: {
            $0.tile == .overview
        }) {
            inputs.append(.overview(
                slotID: "period-\(row.id.id)-overview",
                data: row.overviewData,
                size: size(for: placement.frame, contentWidth: contentWidth)
            ))
        }
        if let route = row.frequentRouteData,
           let placement = recipe.placements.first(where: {
               $0.tile == .frequentRoute
           }) {
            inputs.append(.overview(
                slotID: "period-\(row.id.id)-frequent-route",
                data: route,
                size: size(for: placement.frame, contentWidth: contentWidth)
            ))
        }
        if let journey = row.longestJourneyData,
           let placement = recipe.placements.first(where: {
               $0.tile == .longestJourney
           }) {
            inputs.append(.overview(
                slotID: "period-\(row.id.id)-longest-journey",
                data: journey,
                size: size(for: placement.frame, contentWidth: contentWidth)
            ))
        }
        return inputs
    }

    private func size(
        for frame: DaySummaryNormalizedFrame,
        contentWidth: CGFloat
    ) -> CGSize {
        CGSize(
            width: frame.width * contentWidth,
            height: frame.height * contentWidth
        )
    }
}
