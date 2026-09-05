import UIKit

/// Keep clipping in points, outside the bitmap that stretches during a morph.
@MainActor
struct HomeFeedZoomTileSnapshot {
    struct CornerRegion {
        let frame: CGRect
        let radius: CGFloat
    }

    let image: UIImage
    let regions: [CornerRegion]

    static func capture(_ view: UIView, background: UIColor,
                        displayScale: CGFloat) -> HomeFeedZoomTileSnapshot {
        let regionViews = (view as? UIKitPhotoSummaryTileView)?.transitionPhotoViews ?? [view]
        let regions = regionViews.map {
            CornerRegion(frame: $0.convert($0.bounds, to: view), radius: $0.layer.cornerRadius)
        }
        // Some map tiles clip both the container and its full-size image child.
        // Photo grids also clip their count overlay. Remove those duplicate
        // silhouette clips for this synchronous capture, then restore them before
        // UIKit can commit a frame. Interior details (e.g. avatars) stay intact.
        var roundedLayers: [(CALayer, CGFloat)] = []
        func collect(_ child: UIView) {
            let frame = child.convert(child.bounds, to: view)
            if child.layer.cornerRadius > 0, regions.contains(where: { $0.frame == frame }) {
                roundedLayers.append((child.layer, child.layer.cornerRadius))
            }
            child.subviews.forEach(collect)
        }
        collect(view)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, _) in roundedLayers { layer.cornerRadius = 0 }
        defer {
            for (layer, radius) in roundedLayers { layer.cornerRadius = radius }
            CATransaction.commit()
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(displayScale * 2,
                           2_048 / max(1, max(view.bounds.width, view.bounds.height)))
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: view.bounds.size))
            context.cgContext.translateBy(x: -view.bounds.minX, y: -view.bounds.minY)
            view.layer.render(in: context.cgContext)
        }
        return Self(image: image, regions: regions.map {
            CornerRegion(frame: $0.frame.offsetBy(dx: -view.bounds.minX, dy: -view.bounds.minY),
                         radius: $0.radius)
        })
    }
}

@MainActor
final class HomeFeedZoomTileImageView: UIImageView {
    private let snapshot: HomeFeedZoomTileSnapshot
    private let shape = CAShapeLayer()

    init(snapshot: HomeFeedZoomTileSnapshot) {
        self.snapshot = snapshot
        super.init(image: snapshot.image)
        disableImplicitAnimations(for: shape)
        shape.actions?["path"] = NSNull()
        layer.mask = shape
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateClipping()
    }

    func updateClipping() {
        let scale = CGAffineTransform(scaleX: bounds.width / snapshot.image.size.width,
                                      y: bounds.height / snapshot.image.size.height)
        let path = UIBezierPath()
        for region in snapshot.regions {
            let rect = region.frame.applying(scale)
            path.append(UIBezierPath(roundedRect: rect, cornerRadius: region.radius))
        }
        shape.frame = bounds
        shape.path = path.cgPath
    }
}

/// A transition-only overlay. The collection view remains the sole live feed;
/// at rest this owns no snapshots, tile views, or display link.
@MainActor
final class HomeFeedZoomTransition: NSObject {
    private final class Scene {
        let scale: JournalSummaryScale
        let anchor: HomeFeedAnchor?
        let offset: CGPoint
        let image: UIImage
        let view: UIImageView
        let tiles: [HomeFeedZoomTile]
        var tileImages: [String: HomeFeedZoomTileSnapshot]
        var weight: HomeFeedZoomSpring
        let backgroundColor: UIColor

        init(scale: JournalSummaryScale, anchor: HomeFeedAnchor?, offset: CGPoint,
             image: UIImage, tiles: [HomeFeedZoomTile], weight: Double,
             backgroundColor: UIColor, tileImages: [String: HomeFeedZoomTileSnapshot]) {
            self.scale = scale
            self.anchor = anchor
            self.offset = offset
            self.image = image
            self.backgroundColor = backgroundColor
            self.tiles = tiles
            self.tileImages = tileImages
            self.weight = HomeFeedZoomSpring(weight)
            view = UIImageView(image: image)
            view.frame = CGRect(origin: .zero, size: image.size)
        }

        func cutOut(_ rect: CGRect) {
            // Keep the surface opaque where a tile was lifted. A transparent
            // layer mask exposed the other zoom level through the empty slot.
            let cover = UIView(frame: rect)
            cover.backgroundColor = backgroundColor
            view.addSubview(cover)
        }

        func croppedTile(_ tile: HomeFeedZoomTile) -> HomeFeedZoomTileSnapshot? {
            if let image = tileImages[tile.id] { return image }
            let rect = tile.frame.applying(CGAffineTransform(scaleX: image.scale, y: image.scale))
            guard let cgImage = image.cgImage?.cropping(to: rect) else { return nil }
            let crop = UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
            return HomeFeedZoomTileSnapshot(image: crop, regions: [
                .init(frame: CGRect(origin: .zero, size: crop.size), radius: 16)
            ])
        }
    }

    private final class FlyingTile {
        let view = UIView()
        var endpoints: [JournalSummaryScale: HomeFeedZoomTile] = [:]
        var images: [JournalSummaryScale: HomeFeedZoomTileImageView] = [:]
        var x: HomeFeedZoomSpring
        var y: HomeFeedZoomSpring
        var width: HomeFeedZoomSpring
        var height: HomeFeedZoomSpring

        init(frame: CGRect) {
            x = HomeFeedZoomSpring(frame.midX)
            y = HomeFeedZoomSpring(frame.midY)
            width = HomeFeedZoomSpring(frame.width)
            height = HomeFeedZoomSpring(frame.height)
            view.isUserInteractionEnabled = false
            view.clipsToBounds = true
        }

        @discardableResult
        func attach(_ tile: HomeFeedZoomTile, scene: Scene) -> Bool {
            guard let image = scene.croppedTile(tile) else { return false }
            endpoints[scene.scale] = tile
            let imageView = HomeFeedZoomTileImageView(snapshot: image)
            images[scene.scale] = imageView
            view.addSubview(imageView)
            scene.cutOut(tile.frame)
            return true
        }

        func retarget(to scale: JournalSummaryScale) {
            guard let tile = endpoints[scale] else { return }
            x.target = tile.frame.midX
            y.target = tile.frame.midY
            width.target = tile.frame.width
            height.target = tile.frame.height
        }

        func advance(by delta: TimeInterval) {
            x.advance(by: delta)
            y.advance(by: delta)
            width.advance(by: delta)
            height.advance(by: delta)
        }

        var isSettled: Bool {
            x.isSettled && y.isSettled && width.isSettled && height.isSettled
        }
    }

    /// CADisplayLink retains its target. A weak proxy prevents a controller cycle.
    private final class DisplayLinkTarget: NSObject {
        weak var owner: HomeFeedZoomTransition?
        @objc func tick(_ link: CADisplayLink) {
            guard let owner else { link.invalidate(); return }
            owner.tick(link)
        }
    }

    private weak var container: UIView?
    private weak var collectionView: UICollectionView?
    private let overlay = UIView()
    private var scenes: [Scene] = []
    private var flyingTiles: [FlyingTile] = []
    private var depth = HomeFeedZoomSpring(0)
    private var destination: JournalSummaryScale = .days
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var isPreparing = false
    private var reduceMotion = false
    var onCompletion: (() -> Void)?
    var isActive: Bool { !scenes.isEmpty }

    func begin(in container: UIView, collectionView: UICollectionView,
               scale: JournalSummaryScale, anchor: HomeFeedAnchor?,
               tiles: [HomeFeedZoomTile]) {
        guard !isActive, container.window != nil,
              collectionView.bounds.width > 0, collectionView.bounds.height > 0 else { return }
        self.container = container
        self.collectionView = collectionView
        reduceMotion = UIAccessibility.isReduceMotionEnabled
        overlay.frame = collectionView.bounds
        overlay.accessibilityIdentifier = "home-feed-zoom-overlay"
        overlay.backgroundColor = .systemGroupedBackground
        overlay.clipsToBounds = true
        overlay.isUserInteractionEnabled = false
        overlay.accessibilityElementsHidden = true
        depth = HomeFeedZoomSpring(scale.zoomDepth)
        destination = scale
        let scene = capture(collectionView, scale: scale, anchor: anchor,
                            tiles: tiles, weight: 1)
        scenes = [scene]
        overlay.addSubview(scene.view)
        // Keep transition content inside the native scroll-edge effect. A
        // sibling overlay covers that effect and removes the toolbar's blur.
        collectionView.addSubview(overlay)
        synchronizeViewport()
        isPreparing = true
    }

    func synchronizeViewport() {
        guard isActive, let collectionView else { return }
        // Reloads change the content offset and insert cells. Pin the overlay
        // to the viewport and keep it above those cells, inside the scroll view.
        overlay.frame = collectionView.bounds
        // Native edge-effect views are also scroll-view children. Going to the
        // front covers them; insert immediately above the highest content cell.
        let contentCells = Set(collectionView.visibleCells.map(ObjectIdentifier.init))
        if let topCell = collectionView.subviews.last(where: { contentCells.contains(ObjectIdentifier($0)) }) {
            collectionView.insertSubview(overlay, aboveSubview: topCell)
        } else {
            collectionView.insertSubview(overlay, at: 0)
        }
    }

    func prepareForRetarget() {
        isPreparing = isActive
    }

    func hasScene(for scale: JournalSummaryScale) -> Bool {
        scenes.contains { $0.scale == scale }
    }

    /// Returning to an in-flight scene also restores its exact viewport, rather
    /// than jumping its partially visible top card to the top edge.
    func cachedOffset(for scale: JournalSummaryScale, anchor: HomeFeedAnchor?,
                      preservesViewport: Bool = false) -> CGPoint? {
        scenes.first { $0.scale == scale && (preservesViewport || $0.anchor == anchor) }?.offset
    }

    func completePreparation(collectionView: UICollectionView,
                             scale: JournalSummaryScale, anchor: HomeFeedAnchor?,
                             tiles: [HomeFeedZoomTile]) {
        guard isActive else { return }
        synchronizeViewport()
        if !scenes.contains(where: { $0.scale == scale }) {
            let scene = capture(collectionView, scale: scale, anchor: anchor,
                                tiles: tiles, weight: 0)
            // Backgrounds stay below every flying tile, in capture order.
            overlay.insertSubview(scene.view, at: scenes.count)
            if !reduceMotion {
                if flyingTiles.isEmpty, scenes.count == 1, let source = scenes.first {
                    for match in HomeFeedZoomMatcher.matches(from: source.tiles, to: scene.tiles) {
                        let tile = FlyingTile(frame: source.tiles[match.source].frame)
                        guard tile.attach(source.tiles[match.source], scene: source) else { continue }
                        tile.attach(scene.tiles[match.target], scene: scene)
                        flyingTiles.append(tile)
                        overlay.addSubview(tile.view)
                    }
                } else {
                    // Extend existing actors to the third scale. Never tear down an
                    // actor that is moving or exceed the original five-tile budget.
                    let candidates = flyingTiles.enumerated().compactMap { index, tile in
                        (tile.endpoints[destination] ?? scenes.reversed().compactMap {
                            tile.endpoints[$0.scale]
                        }.first).map { (index, $0) }
                    }
                    for match in HomeFeedZoomMatcher.matches(from: candidates.map(\.1), to: scene.tiles) {
                        flyingTiles[candidates[match.source].0].attach(scene.tiles[match.target], scene: scene)
                    }
                }
            }
            scenes.append(scene)
            // Actors retain only selected images. Drop every unused candidate
            // as soon as matching finishes, including on the third destination.
            for captured in scenes { captured.tileImages.removeAll() }
        }
        destination = scale
        depth.target = scale.zoomDepth
        for scene in scenes { scene.weight.target = scene.scale == scale ? 1 : 0 }
        for tile in flyingTiles { tile.retarget(to: scale) }
        isPreparing = false
        render()
        startDisplayLink()
    }

    func finish() {
        guard isActive else { return }
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        overlay.removeFromSuperview()
        collectionView = nil
        overlay.subviews.forEach { $0.removeFromSuperview() }
        scenes.removeAll()
        flyingTiles.removeAll()
        isPreparing = false
        onCompletion?()
    }

    private func capture(_ collectionView: UICollectionView,
                         scale: JournalSummaryScale, anchor: HomeFeedAnchor?,
                         tiles: [HomeFeedZoomTile], weight: Double) -> Scene {
        let format = UIGraphicsImageRendererFormat()
        let displayScale = max(1, collectionView.traitCollection.displayScale)
        format.scale = displayScale
        format.opaque = true
        let bounds = CGRect(origin: .zero, size: collectionView.bounds.size)
        let background = (collectionView.backgroundColor ?? .systemGroupedBackground)
            .resolvedColor(with: collectionView.traitCollection)
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            background.setFill()
            context.fill(bounds)
            // These maps and avatars are UIImageViews, not live map surfaces.
            // Render their model layers so images assigned by cache preparation
            // are captured even before a render-server commit. Rendering visible
            // cells also avoids snapshotting the scroll edge's blur/mask surface.
            for cell in collectionView.visibleCells.sorted(by: { $0.frame.minY < $1.frame.minY }) {
                let frame = cell.convert(cell.bounds, to: collectionView)
                    .offsetBy(dx: -collectionView.bounds.minX, dy: -collectionView.bounds.minY)
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: frame.minX, y: frame.minY)
                cell.layer.render(in: context.cgContext)
                context.cgContext.restoreGState()
            }
        }
        var tileImages: [String: HomeFeedZoomTileSnapshot] = [:]
        if !reduceMotion {
            for tile in tiles {
                guard let view = tile.view else { continue }
                // Render from the original tile, not from the viewport bitmap.
                // Extra samples preserve text and shapes as a small day tile
                // expands. Bound the longest texture edge to control peak cost.
                tileImages[tile.id] = HomeFeedZoomTileSnapshot.capture(view,
                    background: background, displayScale: displayScale)
            }
        }
        return Scene(scale: scale, anchor: anchor, offset: collectionView.contentOffset,
                     image: image, tiles: tiles, weight: weight, backgroundColor: background,
                     tileImages: tileImages)
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let target = DisplayLinkTarget()
        target.owner = self
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
        let maximum = Float(container?.window?.windowScene?.screen.maximumFramesPerSecond ?? 60)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum),
                                                       maximum: maximum, preferred: maximum)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func tick(_ link: CADisplayLink) {
        guard container?.window != nil,
              container?.bounds.size == overlay.bounds.size,
              reduceMotion == UIAccessibility.isReduceMotionEnabled else { finish(); return }
        let timestamp = link.targetTimestamp
        let delta = min(0.1, max(0, timestamp - (lastTimestamp ?? link.timestamp)))
        lastTimestamp = timestamp
        advance(by: delta)
    }

    // Kept separate from the display link so continuity and cleanup can be
    // verified deterministically at different refresh rates.
    func advance(by delta: TimeInterval) {
        // Existing motion continues while a new destination resolves cached
        // images. Another button tap can cancel that preparation immediately.
        guard isActive else { return }
        depth.advance(by: delta)
        for scene in scenes { scene.weight.advance(by: delta) }
        for tile in flyingTiles { tile.advance(by: delta) }
        render()
        if !isPreparing && depth.isSettled && scenes.allSatisfy({ $0.weight.isSettled })
            && flyingTiles.allSatisfy(\.isSettled) {
            finish()
        }
    }

    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        // Normalize source-over alpha so two half-opacity snapshots don't dim
        // the screen or produce a background flash halfway through the zoom.
        var accumulated = 0.0
        for scene in scenes {
            let weight = max(0, min(1, scene.weight.value))
            accumulated += weight
            scene.view.alpha = accumulated > 0.0001 ? weight / accumulated : 0
            // One shared depth coordinate keeps both backgrounds moving in the
            // same direction, including through reversals and third-level targets.
            let scale = reduceMotion ? 1 : exp((scene.scale.zoomDepth - depth.value) * 0.28)
            scene.view.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
        for tile in flyingTiles {
            tile.view.bounds = CGRect(x: 0, y: 0, width: max(1, tile.width.value),
                                      height: max(1, tile.height.value))
            tile.view.center = CGPoint(x: tile.x.value, y: tile.y.value)
            var total = 0.0
            for scene in scenes {
                guard let image = tile.images[scene.scale] else { continue }
                let weight = max(0, min(1, scene.weight.value))
                total += weight
                image.frame = tile.view.bounds
                image.updateClipping()
                image.alpha = total > 0.0001 ? weight / total : 0
            }
            tile.view.alpha = min(1, total)
        }
    }
}
