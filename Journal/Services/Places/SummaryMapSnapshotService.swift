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

    var slotHash: String { Self.digest(slotID.data(using: .utf8) ?? Data()) }
    var contentHash: String { Self.digest(Self.encoded(content)) }
    var variantHash: String { Self.digest(Self.encoded(variant)) }
    var cacheKey: String { "\(slotHash)/\(contentHash)/\(variantHash)" }

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

@MainActor
enum SummaryMapSnapshotRequestFactory {
    private static let renderVersion = 16

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
        let diameter = PlaceMapCamera.visibleDiameter(
            accuracyRadiusMeters: location.accuracyRadiusMeters,
            minimum: 320
        )
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

        let traits = UITraitCollection(userInterfaceStyle: appearance == .dark
            ? .dark
            : .light)
        let markers = data.markers.map { marker in
            SummaryMapMarkerDescriptor(
                id: marker.id,
                name: marker.name,
                coordinate: SummaryMapCoordinate(
                    latitude: marker.latitude,
                    longitude: marker.longitude
                ),
                systemImageName: marker.systemImage.rawValue,
                color: color(
                    PlaceSymbols.symbol(for: marker.systemImage).primary,
                    traits: traits
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
        let paths = data.paths.map { path in
            let strokes: [SummaryMapPathDescriptor.Stroke]
            switch path.kind {
            case .transit(let transitType):
                strokes = [
                    .init(
                        color: color(
                            TransitPresentationCatalog.presentation(
                                for: transitType
                            ).color.opacity(0.82),
                            traits: traits
                        ),
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

    private static func color(
        _ color: Color,
        traits: UITraitCollection
    ) -> SummaryMapColor {
        let resolved = UIColor(color).resolvedColor(with: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if !resolved.getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        ) {
            var white: CGFloat = 0
            resolved.getWhite(&white, alpha: &alpha)
            red = white
            green = white
            blue = white
        }
        return SummaryMapColor(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }

    private static func evenPixelCount(_ value: CGFloat) -> Int {
        let rounded = Int(value.rounded())
        return rounded.isMultiple(of: 2) ? rounded : rounded + 1
    }
}

actor SummaryMapSnapshotStore {
    typealias Renderer = @Sendable (SummaryMapSnapshotRequest) async throws -> Data

    nonisolated static let shared = SummaryMapSnapshotStore()
    nonisolated static let byteLimit = 100 * 1_024 * 1_024

    private struct InFlight {
        let id: UUID
        let task: Task<Data, any Error>
    }

    private struct MemoryEntry {
        let data: Data
        var access: UInt64
    }

    private let directory: URL
    private let maximumBytes: Int
    private let renderer: Renderer
    private var inFlight: [String: InFlight] = [:]
    private var currentContentBySlot: [String: String] = [:]
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
        self.directory = directory
            ?? caches.appending(path: "SummaryMapSnapshots", directoryHint: .isDirectory)
        self.maximumBytes = maximumBytes
        self.renderer = renderer
    }

    func data(for request: SummaryMapSnapshotRequest) async throws -> Data {
        let key = request.cacheKey
        currentContentBySlot[request.slotHash] = request.contentHash
        if var entry = memory[key] {
            memoryClock &+= 1
            entry.access = memoryClock
            memory[key] = entry
            return entry.data
        }

        try prepareDirectory(for: request)
        let fileURL = fileURL(for: request)
        if let data = try? Data(contentsOf: fileURL), !data.isEmpty {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: fileURL.path
            )
            remember(data, forKey: key)
            return data
        }

        if let existing = inFlight[key] {
            return try await existing.task.value
        }

        let token = UUID()
        let renderer = renderer
        let task = Task<Data, any Error>(priority: .utility) {
            try await SummaryMapRenderLimiter.shared.perform {
                try await renderer(request)
            }
        }
        inFlight[key] = InFlight(id: token, task: task)

        do {
            let data = try await task.value
            if inFlight[key]?.id == token,
               currentContentBySlot[request.slotHash] == request.contentHash {
                try prepareDirectory(for: request)
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: fileURL, options: .atomic)
                remember(data, forKey: key)
                inFlight[key] = nil
                try trimDiskIfNeeded()
            } else if inFlight[key]?.id == token {
                inFlight[key] = nil
            }
            return data
        } catch {
            if inFlight[key]?.id == token {
                inFlight[key] = nil
            }
            throw error
        }
    }

    func prewarm(
        _ requests: [SummaryMapSnapshotRequest],
        retainDecodedImages: Bool = false
    ) async {
        for request in requests {
            guard !Task.isCancelled else { return }
            guard let data = try? await data(for: request) else { continue }
            if retainDecodedImages {
                await SummaryMapDecodedImageCache.insert(
                    data: data,
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
        let children = try fileManager.contentsOfDirectory(
            at: slotDirectory,
            includingPropertiesForKeys: nil
        )
        for child in children where child.lastPathComponent != request.contentHash {
            try? fileManager.removeItem(at: child)
        }
        try fileManager.createDirectory(
            at: contentDirectory,
            withIntermediateDirectories: true
        )
    }

    private func fileURL(for request: SummaryMapSnapshotRequest) -> URL {
        directory
            .appending(path: request.slotHash, directoryHint: .isDirectory)
            .appending(path: request.contentHash, directoryHint: .isDirectory)
            .appending(path: request.variantHash)
            .appendingPathExtension("jpg")
    }

    private func remember(_ data: Data, forKey key: String) {
        memoryClock &+= 1
        if let old = memory[key] { memoryBytes -= old.data.count }
        memory[key] = MemoryEntry(data: data, access: memoryClock)
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

@MainActor
enum SummaryMapDecodedImageCache {
    static func image(for request: SummaryMapSnapshotRequest) -> UIImage? {
        SummaryImageMemoryCache.shared.image(forKey: key(for: request))
    }

    static func insert(data: Data, for request: SummaryMapSnapshotRequest) {
        guard let image = UIImage(
            data: data,
            scale: CGFloat(request.variant.scale)
        ) else { return }
        SummaryImageMemoryCache.shared.insert(
            image,
            forKey: key(for: request),
            cost: request.variant.pixelWidth * request.variant.pixelHeight * 4
        )
    }

    private static func key(for request: SummaryMapSnapshotRequest) -> String {
        "summary-map/\(request.cacheKey)"
    }
}

private actor SummaryMapRenderLimiter {
    static let shared = SummaryMapRenderLimiter(limit: 2)

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
        let image = try await SummaryMapViewRenderer.render(request)
        try Task.checkCancellation()
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data as Data
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
    private var hostWindow: UIWindow?
    private var overlayStyles: [ObjectIdentifier: OverlayStyle] = [:]
    private var continuation: CheckedContinuation<CGImage, any Error>?
    private var timeoutTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var mapIsFullyRendered = false
    private var didFinish = false

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

    init(request: SummaryMapSnapshotRequest) {
        self.request = request
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
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            configureMap()
            timeoutTask = Task { [self] in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                failRendering(with: URLError(.timedOut))
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
            withIdentifier: "summary-map-marker",
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
            // adaptive title policy. Reapply the same native marker settings
            // once the prepared view is installed in either map size.
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
        view.glyphImage = UIImage(systemName: annotation.systemImageName)
        view.displayPriority = .required
        view.titleVisibility = .hidden
    }

    private func scheduleFinishIfReady() {
        guard mapIsFullyRendered,
              finishTask == nil,
              request.content.markers.allSatisfy({ descriptor in
                  mapView.annotations.contains { annotation in
                      guard let annotation = annotation as? Annotation else {
                          return false
                      }
                      return annotation.coordinate.latitude
                          == descriptor.displayCoordinate.latitude
                          && annotation.coordinate.longitude
                          == descriptor.displayCoordinate.longitude
                          && mapView.view(for: annotation)?.window != nil
                  }
              }) else { return }

        // Overview titles are intentionally hidden, so the installed marker
        // views and the fully-rendered map callback are sufficient readiness
        // signals for the cached capture.
        finishTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            prepareMarkerViewsForCapture()
            finishRendering()
        }
    }

    private func prepareMarkerViewsForCapture() {
        for annotation in mapView.annotations {
            guard let annotation = annotation as? Annotation,
                  let view = mapView.view(for: annotation)
                    as? MKMarkerAnnotationView else { continue }
            configure(view, for: annotation)
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
        mapView.setNeedsLayout()
        mapView.layoutIfNeeded()
        CATransaction.flush()
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
        mapView.mapType = .standard
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
            forAnnotationViewWithReuseIdentifier: "summary-map-marker"
        )
        mapView.addAnnotations(
            request.content.markers.map(Annotation.init(marker:))
        )
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
                let overlay = MKPolyline(coordinates: coordinates, count: coordinates.count)
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
            let coordinates = request.content.markers.map(\.displayCoordinate)
                + request.content.paths.flatMap {
                    $0.coordinates.map(\.mapCoordinate)
                }
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
            var rect = MKMapRect.null
            for coordinate in coordinates {
                let point = MKMapPoint(coordinate)
                rect = rect.union(MKMapRect(
                    origin: point,
                    size: MKMapSize(width: 1, height: 1)
                ))
            }
            let latitude = coordinates.map(\.latitude).reduce(0, +)
                / Double(coordinates.count)
            let minimumPadding = 450 * MKMapPointsPerMeterAtLatitude(latitude)
            mapView.setVisibleMapRect(
                rect.insetBy(
                    dx: -max(rect.width * 0.22, minimumPadding),
                    dy: -max(rect.height * 0.22, minimumPadding)
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
        let retainedDayCount = min(newestFirst.count, 60)
        let recentPhotos = newestFirst.prefix(retainedDayCount).flatMap {
            $0.summary.photos.prefix(4)
        }
        let periodPhotos = (monthRows + yearRows).flatMap {
            $0.summary.photos.prefix(4)
        }
        async let photoPrewarm: Void = SummaryPhotoThumbnailService.prewarm(
            recentPhotos + periodPhotos
        )

        // Keep a generous recent window decoded so ordinary day browsing does
        // not flash placeholders as lazy rows are recreated.
        for row in newestFirst.prefix(retainedDayCount) {
            guard !Task.isCancelled else { return }
            await row.loadMapEnrichment()
            let requests = daySnapshotRequests(
                for: row,
                contentWidth: contentWidth,
                displayScale: displayScale,
                appearance: appearance
            )
            await SummaryMapSnapshotStore.shared.prewarm(
                requests,
                retainDecodedImages: true
            )
        }

        // There are comparatively few month and year maps, so retain all of
        // them before spending time on older day snapshots.
        for row in (monthRows + yearRows).reversed() {
            guard !Task.isCancelled else { return }
            await row.loadEnrichment()
            let requests = periodSnapshotRequests(
                for: row,
                contentWidth: contentWidth,
                displayScale: displayScale,
                appearance: appearance
            )
            await SummaryMapSnapshotStore.shared.prewarm(
                requests,
                retainDecodedImages: true
            )
        }


        // Finish the retroactive disk cache for older days without displacing
        // the recent decoded working set.
        for row in newestFirst.dropFirst(retainedDayCount) {
            guard !Task.isCancelled else { return }
            await row.loadMapEnrichment()
            let requests = daySnapshotRequests(
                for: row,
                contentWidth: contentWidth,
                displayScale: displayScale,
                appearance: appearance
            )
            await SummaryMapSnapshotStore.shared.prewarm(requests)
        }
        await photoPrewarm
    }

    private func daySnapshotRequests(
        for row: DaySummaryRowModel,
        contentWidth: CGFloat,
        displayScale: CGFloat,
        appearance: SummaryMapSnapshotRequest.Appearance
    ) -> [SummaryMapSnapshotRequest] {
        let recipe = DaySummaryLayoutRecipe.make(for: row.summary)
        var requests: [SummaryMapSnapshotRequest] = []
        if let placement = recipe.placements.first(where: { $0.tile == .overview }),
           let request = SummaryMapSnapshotRequestFactory.overview(
               slotID: "day-\(row.id.id)-overview",
               data: row.overviewData,
               size: size(for: placement.frame, contentWidth: contentWidth),
               displayScale: displayScale,
               appearance: appearance
           ) {
            requests.append(request)
        }
        return requests
    }

    private func periodSnapshotRequests(
        for row: PeriodSummaryRowModel,
        contentWidth: CGFloat,
        displayScale: CGFloat,
        appearance: SummaryMapSnapshotRequest.Appearance
    ) -> [SummaryMapSnapshotRequest] {
        let recipe = row.layoutRecipe
        var requests: [SummaryMapSnapshotRequest] = []

        if let placement = recipe.placements.first(where: { $0.tile == .overview }),
           let request = SummaryMapSnapshotRequestFactory.overview(
               slotID: "period-\(row.id.id)-overview",
               data: row.overviewData,
               size: size(for: placement.frame, contentWidth: contentWidth),
               displayScale: displayScale,
               appearance: appearance
           ) {
            requests.append(request)
        }
        if let route = row.frequentRouteData,
           let placement = recipe.placements.first(where: {
               $0.tile == .frequentRoute
           }),
           let request = SummaryMapSnapshotRequestFactory.overview(
               slotID: "period-\(row.id.id)-frequent-route",
               data: route,
               size: size(for: placement.frame, contentWidth: contentWidth),
               displayScale: displayScale,
               appearance: appearance
           ) {
            requests.append(request)
        }
        if let journey = row.longestJourneyData,
           let placement = recipe.placements.first(where: {
               $0.tile == .longestJourney
           }),
           let request = SummaryMapSnapshotRequestFactory.overview(
               slotID: "period-\(row.id.id)-longest-journey",
               data: journey,
               size: size(for: placement.frame, contentWidth: contentWidth),
               displayScale: displayScale,
               appearance: appearance
           ) {
            requests.append(request)
        }
        return requests
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
