import UIKit

@MainActor
enum UIKitHomeFeedAssetPrefetcher {
    static func prefetch(
        day row: DaySummaryRowModel,
        contentWidth: CGFloat,
        displayScale: CGFloat,
        appearance: SummaryMapSnapshotRequest.Appearance
    ) async {
        async let photos: Void = SummaryPhotoThumbnailService.prewarm(
            Array(row.summary.photos.prefix(4))
        )
        async let contacts: Void = prefetchContacts(row.summary.people)

        let inputs = mapRequestInputs(
            day: row,
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
        _ = await (photos, contacts)
    }

    static func prefetch(
        period row: PeriodSummaryRowModel,
        contentWidth: CGFloat,
        displayScale: CGFloat,
        appearance: SummaryMapSnapshotRequest.Appearance
    ) async {
        async let photos: Void = SummaryPhotoThumbnailService.prewarm(
            Array(row.summary.photos.prefix(4))
        )
        async let contacts: Void = prefetchContacts(
            row.summary.people.map(\.person)
        )

        let inputs = mapRequestInputs(
            period: row,
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
        _ = await (photos, contacts)
    }

    private static func prefetchContacts(
        _ people: [TimelinePersonSnapshot]
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for person in people.prefix(18) {
                guard let identifier = person.contactIdentifier else { continue }
                group.addTask {
                    _ = await UIKitContactAvatarStore.shared.image(
                        for: identifier
                    )
                }
            }
        }
    }

    private static func mapRequestInputs(
        day row: DaySummaryRowModel,
        contentWidth: CGFloat
    ) -> [SummaryMapSnapshotRequestInput] {
        row.layoutRecipe.placements.compactMap { placement in
            let size = size(for: placement.frame, contentWidth: contentWidth)
            switch placement.tile {
            case .overview:
                return .overview(
                    slotID: "day-\(row.id.id)-overview",
                    data: row.overviewData,
                    size: size
                )
            case .featuredPlace:
                guard let place = row.summary.featuredPlace else { return nil }
                return .place(
                    slotID: "day-\(row.id.id)-featured-place",
                    location: place.location,
                    size: size
                )
            default:
                return nil
            }
        }
    }

    private static func mapRequestInputs(
        period row: PeriodSummaryRowModel,
        contentWidth: CGFloat
    ) -> [SummaryMapSnapshotRequestInput] {
        row.layoutRecipe.placements.compactMap { placement in
            let size = size(for: placement.frame, contentWidth: contentWidth)
            switch placement.tile {
            case .overview:
                return .overview(
                    slotID: "period-\(row.id.id)-overview",
                    data: row.overviewData,
                    size: size
                )
            case .frequentRoute:
                guard let route = row.frequentRouteData else { return nil }
                return .overview(
                    slotID: "period-\(row.id.id)-frequent-route",
                    data: route,
                    size: size
                )
            case .longestJourney:
                guard let journey = row.longestJourneyData else { return nil }
                return .overview(
                    slotID: "period-\(row.id.id)-longest-journey",
                    data: journey,
                    size: size
                )
            case .place:
                guard let place = row.summary.mostVisitedPlace else { return nil }
                return .place(
                    slotID: "period-\(row.id.id)-place",
                    location: place.location,
                    size: size
                )
            default:
                return nil
            }
        }
    }

    static func overviewData(
        for location: TimelineLocationSnapshot
    ) -> TimelineOverviewData {
        guard location.hasCoordinate else { return TimelineOverviewData() }
        return TimelineOverviewData(
            markers: [TimelineMapMarker(location: location)],
            paths: []
        )
    }

    private static func size(
        for frame: DaySummaryNormalizedFrame,
        contentWidth: CGFloat
    ) -> CGSize {
        CGSize(
            width: frame.width * contentWidth,
            height: frame.height * contentWidth
        )
    }
}

actor UIKitContactAvatarStore {
    static let shared = UIKitContactAvatarStore()

    private let images = NSCache<NSString, UIImage>()
    private var tasks: [String: Task<UIImage?, Never>] = [:]

    init() {
        images.countLimit = 128
        images.totalCostLimit = 24 * 1_024 * 1_024
    }

    func cachedImage(for identifier: String) -> UIImage? {
        images.object(forKey: identifier as NSString)
    }

    func image(for identifier: String) async -> UIImage? {
        if let image = cachedImage(for: identifier) { return image }
        if let task = tasks[identifier] { return await task.value }

        let task = Task<UIImage?, Never> {
            guard let data = try? await ContactsService.shared.photoData(
                for: identifier
            ),
            let encoded = UIImage(data: data) else { return nil }
            return await encoded.byPreparingForDisplay() ?? encoded
        }
        tasks[identifier] = task
        let image = await task.value
        tasks[identifier] = nil
        if let image {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
            images.setObject(image, forKey: identifier as NSString, cost: cost)
        }
        return image
    }
}

@MainActor
final class UIKitSummaryMapImageView: UIImageView {
    private enum Source: Equatable, Sendable {
        case overview(TimelineOverviewData)
        case place(TimelineLocationSnapshot)
    }

    private var slotID = ""
    private var source = Source.overview(TimelineOverviewData())
    private var loadsContent = false
    private var requestKey: String?
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        disableImplicitAnimations(for: layer)
        backgroundColor = .secondarySystemGroupedBackground
        contentMode = .scaleAspectFill
        clipsToBounds = true
        layer.cornerRadius = 16
        isAccessibilityElement = true
        registerForTraitChanges([
            UITraitUserInterfaceStyle.self,
            UITraitDisplayScale.self,
        ]) { (view: UIKitSummaryMapImageView, _) in
            view.invalidateTraitDependentImage()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        slotID: String,
        data: TimelineOverviewData,
        loadsContent: Bool,
        accessibilityLabel: String
    ) {
        configure(
            slotID: slotID,
            source: .overview(data),
            loadsContent: loadsContent,
            accessibilityLabel: accessibilityLabel
        )
    }

    func configurePlace(
        slotID: String,
        location: TimelineLocationSnapshot,
        loadsContent: Bool,
        accessibilityLabel: String
    ) {
        configure(
            slotID: slotID,
            source: .place(location),
            loadsContent: loadsContent,
            accessibilityLabel: accessibilityLabel
        )
    }

    private func configure(
        slotID: String,
        source: Source,
        loadsContent: Bool,
        accessibilityLabel: String
    ) {
        let changed = self.slotID != slotID || self.source != source
            || self.loadsContent != loadsContent
        self.slotID = slotID
        self.source = source
        self.loadsContent = loadsContent
        self.accessibilityLabel = accessibilityLabel
        guard changed else { return }
        generation &+= 1
        requestKey = nil
        loadTask?.cancel()
        loadTask = nil
        image = nil
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        loadIfNeeded()
    }

    func cancelLoading() {
        generation &+= 1
        loadTask?.cancel()
        loadTask = nil
        requestKey = nil
    }

    private func invalidateTraitDependentImage() {
        generation &+= 1
        requestKey = nil
        image = nil
        loadTask?.cancel()
        loadTask = nil
        loadIfNeeded()
    }

    private func loadIfNeeded() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard loadTask == nil else { return }
        let appearance: SummaryMapSnapshotRequest.Appearance =
            traitCollection.userInterfaceStyle == .dark ? .dark : .light
        let input: SummaryMapSnapshotRequestInput = switch source {
        case .overview(let data):
            .overview(
                slotID: slotID,
                data: data,
                size: bounds.size
            )
        case .place(let location):
            .place(
                slotID: slotID,
                location: location,
                size: bounds.size
            )
        }
        let displayScale = traitCollection.displayScale
        let loadsContent = loadsContent
        let expectedGeneration = generation
        loadTask = Task { [weak self] in
            defer {
                if self?.generation == expectedGeneration {
                    self?.loadTask = nil
                }
            }
            guard let request = await SummaryMapSnapshotRequestBuilder.request(
                for: input,
                displayScale: displayScale,
                appearance: appearance
            ), !Task.isCancelled,
            self?.generation == expectedGeneration else { return }
            guard self?.requestKey != request.cacheKey else { return }
            self?.requestKey = request.cacheKey

            if let cached = SummaryMapDecodedImageCache.cachedImage(for: request) {
                self?.image = cached
                return
            }

            let expectedKey = request.cacheKey
            let cachedData = await SummaryMapSnapshotStore.shared.cachedData(
                for: request
            )
            let encodedData: Data?
            if let cachedData {
                encodedData = cachedData
            } else if loadsContent {
                encodedData = try? await SummaryMapSnapshotStore.shared.data(
                    for: request
                )
            } else {
                encodedData = nil
            }
            guard let encodedData, !Task.isCancelled,
                  let decoded = await SummaryMapDecodedImageCache.image(
                    data: encodedData,
                    for: request
                  ),
                  !Task.isCancelled,
                  self?.requestKey == expectedKey else { return }
            self?.image = decoded
        }
    }
}

@MainActor
final class UIKitSummaryPhotoView: UIImageView {
    private var reference: PhotoReference?
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        disableImplicitAnimations(for: layer)
        backgroundColor = .tertiarySystemGroupedBackground
        contentMode = .scaleAspectFill
        clipsToBounds = true
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        reference: PhotoReference,
        cornerRadius: CGFloat,
        loadsContent: Bool
    ) {
        layer.cornerRadius = cornerRadius
        accessibilityLabel = String(localized: "Photo")
        let referenceChanged = self.reference?.id != reference.id
        if referenceChanged {
            loadTask?.cancel()
            loadTask = nil
            image = SummaryPhotoThumbnailService.cachedImage(for: reference)
        }
        self.reference = reference
        guard image == nil, loadsContent, loadTask == nil else { return }
        loadTask = Task { [weak self] in
            let image = await SummaryPhotoThumbnailService.image(for: reference)
            guard !Task.isCancelled,
                  self?.reference?.id == reference.id else { return }
            self?.image = image
            self?.loadTask = nil
        }
    }

    func reset() {
        reference = nil
        loadTask?.cancel()
        loadTask = nil
        image = nil
    }
}
