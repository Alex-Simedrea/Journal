import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import Journal

@Suite("UIKit home feed zoom", .serialized)
@MainActor
struct HomeFeedZoomTests {
    private let days = (1...4).map { TimelineDayKey(year: 2026, month: 7, day: $0) }

    @Test("Maps spread across multiple visible days with a strict one-to-one budget")
    func distributedMatches() {
        let period = (0..<4).map { tile("month-\($0)", owner: "month", days: days, y: $0 * 100) }
        let daily = days.enumerated().flatMap { index, day in
            (0..<2).map { tile("day-\(index)-\($0)", owner: day.id, days: [day], y: index * 180 + $0 * 50) }
        }
        let matches = HomeFeedZoomMatcher.matches(from: period, to: daily)
        #expect(matches.count == 4)
        #expect(Set(matches.map { daily[$0.target].owner }).count == 4)
        #expect(Set(matches.map(\.source)).count == matches.count)
        #expect(Set(matches.map(\.target)).count == matches.count)
        let reversed = HomeFeedZoomMatcher.matches(from: daily, to: period)
        #expect(Set(reversed.map { daily[$0.source].owner }).count == 4)
    }

    @Test("Only related dates and the same media family can match")
    func semanticMatching() {
        let source = [tile("map", days: [days[0]]),
                      tile("photo", family: .photos, days: days, ids: ["A"])]
        let unrelated = [tile("other-map", days: [days[1]]),
                         tile("other-photo", family: .photos, days: days, ids: ["B"])]
        #expect(HomeFeedZoomMatcher.matches(from: source, to: unrelated).isEmpty)
        let related = [tile("same-photo", family: .photos, days: days, ids: ["A"])]
        let matches = HomeFeedZoomMatcher.matches(from: source, to: related)
        #expect(matches.count == 1)
        #expect(matches.first?.source == 1)
    }

    @Test("Many common tiles still produce only five moving tiles")
    func boundedAndDeterministic() {
        let source = (0..<20).map { tile("source-\($0)", days: days, y: $0 * 20) }
        let target = (0..<20).map { tile("target-\($0)", days: days, y: $0 * 25) }
        let first = HomeFeedZoomMatcher.matches(from: source, to: target)
        let second = HomeFeedZoomMatcher.matches(from: source, to: target)
        #expect(first.count == 5)
        #expect(first.map(\.source) == second.map(\.source))
        #expect(first.map(\.target) == second.map(\.target))
    }

    @Test("Reversing and retargeting retain position and velocity")
    func springContinuity() {
        var spring = HomeFeedZoomSpring(0)
        spring.target = 1
        for _ in 0..<8 { spring.advance(by: 1.0 / 120) }
        let position = spring.value
        let velocity = spring.velocity
        #expect(position > 0 && position < 1)
        #expect(velocity > 0)
        spring.target = 0
        #expect(spring.value == position)
        #expect(spring.velocity == velocity)
        spring.advance(by: 1.0 / 120)
        #expect(spring.value > position) // Momentum continues before reversing.
        spring.target = 2
        for _ in 0..<240 { spring.advance(by: 1.0 / 120) }
        #expect(spring.isSettled)
        #expect(abs(spring.value - 2) < 0.001)
    }

    @Test("Spring motion is independent of display refresh rate")
    func refreshRates() {
        func value(at rate: Int) -> Double {
            var spring = HomeFeedZoomSpring(500)
            spring.target = 80
            for _ in 0..<(rate / 4) { spring.advance(by: 1 / Double(rate)) }
            return spring.value
        }
        #expect(abs(value(at: 60) - value(at: 120)) < 0.001)
    }

    @Test("An in-flight three-scale session retains actors, reverses and releases its overlay")
    func overlayLifecycle() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        let collection = UICollectionView(frame: controller.view.bounds,
                                           collectionViewLayout: UICollectionViewFlowLayout())
        collection.backgroundColor = .systemTeal
        controller.view.addSubview(collection)
        controller.view.layoutIfNeeded()
        let transition = HomeFeedZoomTransition()
        let anchor = HomeFeedAnchor.day(days[0])
        let source = [tile("day", days: days, y: 120)]
        transition.begin(in: controller.view, collectionView: collection,
                         scale: .days, anchor: anchor, tiles: source)
        #expect(transition.isActive)
        let overlay = try #require(collection.subviews.first {
            $0.accessibilityIdentifier == "home-feed-zoom-overlay"
        })
        transition.completePreparation(collectionView: collection, scale: .months,
            anchor: .period(.month(MonthKey(year: 2026, month: 7))),
            tiles: [tile("month", days: days, y: 240)])
        for _ in 0..<8 { transition.advance(by: 1.0 / 120) }
        #expect(overlay.subviews[0].transform.a < 1)
        #expect(overlay.subviews[1].transform.a > 1)
        let actor = try #require(overlay.subviews.last)
        #expect(actor.layer.cornerRadius == 0) // Each snapshot carries its own shape.
        #expect(actor.subviews.first?.layer.mask is CAShapeLayer)
        #expect(actor.clipsToBounds)
        #expect(overlay.subviews[0].layer.mask == nil)
        #expect(overlay.subviews[0].subviews.first?.backgroundColor != nil)
        let before = actor.frame
        transition.prepareForRetarget()
        transition.completePreparation(collectionView: collection, scale: .years,
            anchor: .period(.year(YearKey(year: 2026))),
            tiles: [tile("year", days: days, y: 360)])
        #expect(overlay.subviews.last === actor)
        #expect(actor.frame == before)
        #expect(overlay.subviews.count <= 3 + HomeFeedZoomMatcher.tileBudget)
        #expect(transition.cachedOffset(for: .days, anchor: anchor) == collection.contentOffset)
        #expect(transition.cachedOffset(for: .days, anchor: .day(days[1])) == nil)
        #expect(transition.cachedOffset(for: .days, anchor: .day(days[1]),
                                       preservesViewport: true) == collection.contentOffset)
        for index in 0..<30 {
            transition.prepareForRetarget()
            transition.completePreparation(collectionView: collection,
                scale: index.isMultiple(of: 2) ? .days : .years,
                anchor: anchor, tiles: [])
            transition.advance(by: 1.0 / 120)
            #expect(overlay.subviews.last === actor)
            #expect(actor.frame.minY.isFinite)
        }
        for _ in 0..<240 { transition.advance(by: 1.0 / 120) }
        #expect(!transition.isActive)
        #expect(overlay.superview == nil)
        #expect(controller.view.subviews.count == 1)
        #expect(collection.alpha == 1)
        #expect(collection.transform == .identity)
        #expect(collection.isScrollEnabled)
        transition.finish() // Idempotent cancellation.
    }

    @Test("Only whole tiles clear of the toolbar viewport can morph")
    func fullyVisibleTiles() {
        let viewport = CGRect(x: 0, y: 100, width: 390, height: 650)
        #expect(tile("bottom-map", days: days, y: 700).fullyVisible(in: viewport) == nil)
        #expect(tile("top-map", days: days, y: 90).fullyVisible(in: viewport) == nil)
        let visible = tile("map", days: days, y: 120)
        #expect(visible.fullyVisible(in: viewport)?.frame == visible.frame)
    }

    @Test("Cached maps are restored before snapshots, including unselected tiles")
    func cachedMapPreparation() async throws {
        let map = UIKitSummaryMapImageView(frame: CGRect(x: 0, y: 0, width: 160, height: 120))
        let location = TimelineLocationSnapshot(name: "Cache fixture", latitude: 44.4, longitude: 26.1)
        let slot = "zoom-test-" + UUID().uuidString
        let input = SummaryMapSnapshotRequestInput.place(slotID: slot, location: location, size: map.bounds.size)
        let request = try #require(input.request(displayScale: map.traitCollection.displayScale,
            appearance: map.traitCollection.userInterfaceStyle == .dark ? .dark : .light))
        let encoded = UIGraphicsImageRenderer(size: map.bounds.size).image { context in
            UIColor.red.setFill()
            context.fill(map.bounds)
        }
        let encodedData = try #require(encoded.pngData())
        let decoded = await SummaryMapDecodedImageCache.image(data: encodedData, for: request)
        let cached = try #require(decoded)
        map.configurePlace(slotID: slot, location: location, loadsContent: false, accessibilityLabel: "Map")
        #expect(map.image == nil)
        await UIKitHomeFeedSnapshotAssets.prepare(in: [map])
        #expect(map.image === cached)
        map.cancelLoading()
    }

    @Test("Transition clipping preserves photo-grid radii in points without changing live tiles")
    func photoSnapshotCorners() throws {
        for style in [UIKitPhotoSummaryTileView.Style.day, .period] {
            for count in [1, 4] {
                let photos = UIKitPhotoSummaryTileView(frame: CGRect(x: 0, y: 0, width: 180, height: 180))
                photos.configure(references: (0..<count).map {
                    PhotoReference(assetLocalIdentifier: "corner-test-\($0)")
                }, totalCount: count == 4 ? 7 : 1, style: style, loadsContent: false)
                photos.layoutIfNeeded()
                for photo in photos.transitionPhotoViews { photo.backgroundColor = .red }
                let originalRadii = photos.transitionPhotoViews.map { $0.layer.cornerRadius }
                let radius: CGFloat = count == 1 ? (style == .day ? 16 : 18) : (style == .day ? 10 : 14)
                #expect(originalRadii.allSatisfy { $0 == radius })
                let snapshot = HomeFeedZoomTileSnapshot.capture(photos, background: .blue, displayScale: 3)
                #expect(photos.transitionPhotoViews.map { $0.layer.cornerRadius } == originalRadii)
                #expect(snapshot.regions.count == count)
                let moving = HomeFeedZoomTileImageView(snapshot: snapshot)
                for factor: CGFloat in [0.55, 1, 2] {
                    moving.frame = CGRect(x: 0, y: 0, width: 180 * factor, height: 180 * factor)
                    moving.layoutIfNeeded()
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 3
                    let rendered = UIGraphicsImageRenderer(size: moving.bounds.size, format: format).image { context in
                        UIColor.blue.setFill()
                        context.fill(moving.bounds)
                        moving.layer.render(in: context.cgContext)
                    }
                    for region in snapshot.regions {
                        let origin = CGPoint(x: region.frame.minX * factor, y: region.frame.minY * factor)
                        // These points straddle the same circular corner at every
                        // size. Baking the radius into the image fails at 0.55x/2x.
                        for (fraction, inside) in [(0.15, false), (0.45, true)] {
                            let point = CGPoint(x: origin.x + radius * fraction, y: origin.y + radius * fraction)
                            let crop = try #require(rendered.cgImage?.cropping(to: CGRect(
                                x: point.x * rendered.scale, y: point.y * rendered.scale, width: 1, height: 1)))
                            var pixel = [UInt8](repeating: 0, count: 4)
                            try pixel.withUnsafeMutableBytes { bytes in
                                let context = try #require(CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                    bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                                context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                            }
                            #expect(inside ? pixel[0] > 80 && pixel[2] < 30 : pixel[2] > 220 && pixel[0] < 30)
                        }
                    }
                }
            }
        }
    }

    @Test("Source snapshots preserve uncommitted map and avatar image layers")
    func snapshotMediaLayers() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 180)
        let collection = UICollectionView(frame: controller.view.bounds, collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "media")
        let source = MediaDataSource()
        collection.dataSource = source
        controller.view.addSubview(collection)
        collection.reloadData()
        collection.layoutIfNeeded()
        let cell = try #require(collection.visibleCells.first)
        let map = UIKitSummaryMapImageView(frame: CGRect(x: 10, y: 10, width: 100, height: 100))
        let avatar = UIKitContactAvatarView(frame: CGRect(x: 150, y: 10, width: 60, height: 60))
        cell.contentView.addSubview(map)
        cell.contentView.addSubview(avatar)
        avatar.layoutIfNeeded()
        func solid(_ color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            }
        }
        map.image = solid(.red)
        let avatarImage = try #require(avatar.subviews.compactMap { $0 as? UIImageView }.first)
        avatarImage.image = solid(.green)
        let transition = HomeFeedZoomTransition()
        let mapTile = HomeFeedZoomTile(id: "map", owner: "day", role: "overview", family: .map,
            days: Set(days), contentIDs: [], frame: map.convert(map.bounds, to: controller.view), view: map)
        transition.begin(in: controller.view, collectionView: collection, scale: .days,
                         anchor: nil, tiles: [mapTile])
        defer { transition.finish() }
        let overlay = try #require(collection.subviews.first {
            $0.accessibilityIdentifier == "home-feed-zoom-overlay"
        })
        let snapshot = try #require((overlay.subviews.first as? UIImageView)?.image)
        #expect(snapshot.scale == collection.traitCollection.displayScale)
        func pixel(at point: CGPoint) throws -> [UInt8] {
            let crop = try #require(snapshot.cgImage?.cropping(to: CGRect(
                x: point.x * snapshot.scale, y: point.y * snapshot.scale, width: 1, height: 1)))
            var bytes = [UInt8](repeating: 0, count: 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try #require(CGContext(data: buffer.baseAddress, width: 1, height: 1,
                    bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            return bytes
        }
        let red = try pixel(at: map.convert(CGPoint(x: 50, y: 50), to: controller.view))
        let green = try pixel(at: avatar.convert(CGPoint(x: 30, y: 30), to: controller.view))
        #expect(red[0] > 200 && red[1] < 50)
        #expect(green[1] > 200 && green[0] < 50)
        transition.completePreparation(collectionView: collection, scale: .months, anchor: nil, tiles: [mapTile])
        let actor = try #require(overlay.subviews.last)
        let movingImage = try #require((actor.subviews.first as? UIImageView)?.image)
        #expect(movingImage.scale == collection.traitCollection.displayScale * 2)
        #expect(movingImage.cgImage!.width >= Int(map.bounds.width * movingImage.scale))
    }

    @Test("Transition content stays inside the native toolbar scroll-edge effects")
    func nativeToolbarBlur() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.title = "Zoom Preview"
        controller.navigationItem.largeTitleDisplayMode = .always
        controller.toolbarItems = [UIBarButtonItem(title: "Years"), .flexibleSpace(),
            UIBarButtonItem(title: "Months"), .flexibleSpace(), UIBarButtonItem(title: "Days")]
        let navigation = UINavigationController(rootViewController: controller)
        navigation.navigationBar.prefersLargeTitles = true
        navigation.setToolbarHidden(false, animated: false)
        window.rootViewController = navigation
        window.isHidden = false
        defer { window.isHidden = true }
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: window.bounds.width - 32, height: 240)
        let collection = UICollectionView(frame: controller.view.bounds, collectionViewLayout: layout)
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collection.backgroundColor = .systemGroupedBackground
        collection.topEdgeEffect.style = .soft
        collection.bottomEdgeEffect.style = .soft
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "media")
        let source = MediaDataSource()
        source.count = 8
        source.configure = { cell, indexPath in
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            let label = UILabel(frame: cell.contentView.bounds)
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            label.numberOfLines = 0
            label.font = .boldSystemFont(ofSize: 30)
            label.text = Array(repeating: "Journal day \(indexPath.item + 1)", count: 6).joined(separator: "\n")
            label.backgroundColor = indexPath.item.isMultiple(of: 2) ? .systemTeal : .systemOrange
            cell.contentView.addSubview(label)
        }
        collection.dataSource = source
        controller.view.addSubview(collection)
        controller.setContentScrollView(collection)
        collection.reloadData()
        window.layoutIfNeeded()
        collection.setContentOffset(CGPoint(x: 0, y: 90), animated: false)
        try await Task.sleep(for: .milliseconds(100))
        func capture(_ name: String) throws -> UIImage {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            Attachment.record(try #require(image.pngData()), named: name)
            return image
        }
        let before = try capture("Native-toolbars-before.png")
        let transition = HomeFeedZoomTransition()
        transition.begin(in: controller.view, collectionView: collection, scale: .days, anchor: nil, tiles: [])
        defer { transition.finish() }
        try await Task.sleep(for: .milliseconds(50))
        let overlay = try #require(collection.subviews.first {
            $0.accessibilityIdentifier == "home-feed-zoom-overlay"
        })
        #expect(overlay.superview === collection)
        #expect(overlay.frame == collection.bounds)
        #expect(!collection.topEdgeEffect.isHidden && !collection.bottomEdgeEffect.isHidden)
        let overlayIndex = try #require(collection.subviews.firstIndex(of: overlay))
        for cell in collection.visibleCells {
            let cellIndex = try #require(collection.subviews.firstIndex(of: cell))
            #expect(cellIndex < overlayIndex, "The transition must cover live cells, not sit behind them.")
        }
        let during = try capture("Native-toolbars-during.png")
        func edgePixels(_ image: UIImage) throws -> [UInt8] {
            let crop = try #require(image.cgImage?.cropping(to: CGRect(x: 0, y: 0,
                width: image.size.width * image.scale, height: 60 * image.scale)))
            var pixels = [UInt8](repeating: 0, count: 32 * 8 * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try #require(CGContext(data: buffer.baseAddress, width: 32, height: 8,
                    bitsPerComponent: 8, bytesPerRow: 32 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.interpolationQuality = .high
                context.draw(crop, in: CGRect(x: 0, y: 0, width: 32, height: 8))
            }
            return pixels
        }
        let beforePixels = try edgePixels(before)
        let duringPixels = try edgePixels(during)
        let error = zip(beforePixels, duringPixels).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) }
            / Double(beforePixels.count)
        #expect(error < 12, "The progressive toolbar blur must survive overlay insertion (pixel error: \(error)).")
    }

    @Test("The real reusable feed restores its offset after rapid scale changes")
    func collectionIntegration() async throws {
        let store = try ModelContainer(for: LogEntry.self, Person.self, Place.self,
            TransitDetails.self, PlaceVisitDetails.self, WorkoutDetails.self, TransitType.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let controller = HomeFeedViewController()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        let dayRows = HomeFeedZoomGalleryFixtures.days
        let months = HomeFeedZoomGalleryFixtures.months
        let years = HomeFeedZoomGalleryFixtures.years
        func update(_ scale: JournalSummaryScale) {
            let anchor: HomeFeedAnchor = switch scale {
            case .days: .day(dayRows[0].id)
            case .months: .period(months[0].id)
            case .years: .period(years[0].id)
            }
            controller.update(modelContext: store.mainContext, dayRows: dayRows,
                monthRows: months, yearRows: years, errorMessage: nil,
                scale: scale, contentRevision: 0, emptyTransitionDay: dayRows[0].id,
                scrollRequest: HomeFeedScrollRequest(scale: scale, anchor: anchor, alignment: .top,
                                                     preservesZoomViewport: true),
                callbacks: .init(onVisibleAnchorChange: { _, _ in }, onScrollRequestApplied: { _ in },
                    onUserScroll: {}, onOpenDay: { _ in }, onOpenPeriod: { _ in },
                    onOpenPeriodDay: { _, _ in }, onStartToday: {},
                    onTimelineDayChange: { .day($0) }, onTimelineDismiss: {}))
        }
        update(.days)
        try await Task.sleep(for: .milliseconds(100))
        let collection = try #require(controller.view.subviews.first as? UICollectionView)
        collection.setContentOffset(CGPoint(x: 0, y: 40), animated: false)
        collection.layoutIfNeeded()
        let originalOffset = collection.contentOffset
        update(.months)
        // Cold simulator caches can take longer than one animation frame. Wait
        // for preparation, then exercise actual in-flight reversals.
        for _ in 0..<200 {
            let overlay = collection.subviews.first { $0.accessibilityIdentifier == "home-feed-zoom-overlay" }
            if overlay?.subviews.count ?? 0 > 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.view.subviews.count == 1)
        let overlay = try #require(collection.subviews.first {
            $0.accessibilityIdentifier == "home-feed-zoom-overlay"
        })
        #expect(overlay.subviews.count > 2) // Backgrounds plus actual matched tiles.
        update(.years)
        try await Task.sleep(for: .milliseconds(40))
        update(.days)
        try await Task.sleep(for: .milliseconds(40))
        #expect(collection.contentOffset == originalOffset)
        #expect(overlay.superview === collection)
        #expect(overlay.frame == collection.bounds)
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        Attachment.record(try #require(image.pngData()), named: "UIKit-home-zoom-midflight.png")
        controller.scrollViewWillBeginDragging(collection)
        #expect(overlay.superview == nil)
        #expect(controller.view.subviews.count == 1)
        #expect(collection.isScrollEnabled)
        #expect(collection.transform == .identity)
    }

    private func tile(_ id: String, owner: String = "card",
                      family: HomeFeedZoomTile.Family = .map,
                      days: [TimelineDayKey], ids: Set<String> = [], y: Int = 100) -> HomeFeedZoomTile {
        HomeFeedZoomTile(id: id, owner: owner, role: id, family: family,
                        days: Set(days), contentIDs: ids,
                        frame: CGRect(x: 16, y: y, width: 100, height: 80))
    }
}

@MainActor
private final class MediaDataSource: NSObject, UICollectionViewDataSource {
    var count = 1
    var configure: ((UICollectionViewCell, IndexPath) -> Void)?
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "media", for: indexPath)
        configure?(cell, indexPath)
        return cell
    }
}
