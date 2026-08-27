import SwiftUI
import SwiftData
import UIKit

struct UIKitHomeFeed: UIViewControllerRepresentable {
    let modelContext: ModelContext
    let model: HomeFeedModel
    let scale: JournalSummaryScale
    let contentRevision: Int
    let emptyTransitionDay: TimelineDayKey
    let scrollRequest: HomeFeedScrollRequest?
    let onVisibleAnchorChange: (JournalSummaryScale, HomeFeedAnchor) -> Void
    let onScrollRequestApplied: (UUID) -> Void
    let onUserScroll: () -> Void
    let onOpenDay: (TimelineDayKey) -> Void
    let onOpenPeriod: (PeriodSummary) -> Void
    let onOpenPeriodDay: (TimelineDayKey, PeriodSummaryKey) -> Void
    let onStartToday: () -> Void
    let onTimelineDayChange: (TimelineDayKey) -> HomeTransitionSource
    let onTimelineDismiss: () -> Void

    func makeUIViewController(context: Context) -> HomeFeedViewController {
        HomeFeedViewController()
    }

    func updateUIViewController(
        _ controller: HomeFeedViewController,
        context: Context
    ) {
        controller.update(
            modelContext: modelContext,
            dayRows: model.rows,
            monthRows: model.monthRows,
            yearRows: model.yearRows,
            errorMessage: model.errorMessage,
            scale: scale,
            contentRevision: contentRevision,
            emptyTransitionDay: emptyTransitionDay,
            scrollRequest: scrollRequest,
            callbacks: HomeFeedViewController.Callbacks(
                onVisibleAnchorChange: onVisibleAnchorChange,
                onScrollRequestApplied: onScrollRequestApplied,
                onUserScroll: onUserScroll,
                onOpenDay: onOpenDay,
                onOpenPeriod: onOpenPeriod,
                onOpenPeriodDay: onOpenPeriodDay,
                onStartToday: onStartToday,
                onTimelineDayChange: onTimelineDayChange,
                onTimelineDismiss: onTimelineDismiss
            )
        )
    }
}

@MainActor
final class HomeFeedViewController: UIViewController {
    struct Callbacks {
        let onVisibleAnchorChange: (JournalSummaryScale, HomeFeedAnchor) -> Void
        let onScrollRequestApplied: (UUID) -> Void
        let onUserScroll: () -> Void
        let onOpenDay: (TimelineDayKey) -> Void
        let onOpenPeriod: (PeriodSummary) -> Void
        let onOpenPeriodDay: (TimelineDayKey, PeriodSummaryKey) -> Void
        let onStartToday: () -> Void
        let onTimelineDayChange: (TimelineDayKey) -> HomeTransitionSource
        let onTimelineDismiss: () -> Void
    }

    nonisolated private enum ItemID: Hashable, Sendable {
        case day(TimelineDayKey)
        case period(PeriodSummaryKey)
        case empty(TimelineDayKey)
        case error(String)

        var anchor: HomeFeedAnchor? {
            switch self {
            case .day(let day): .day(day)
            case .period(let period): .period(period)
            case .empty, .error: nil
            }
        }
    }

    private let layout = UICollectionViewFlowLayout()
    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: layout
    )
    private var dataSource: UICollectionViewDiffableDataSource<Int, ItemID>!

    private var dayRows: [TimelineDayKey: DaySummaryRowModel] = [:]
    private var periodRows: [PeriodSummaryKey: PeriodSummaryRowModel] = [:]
    private var modelContext: ModelContext?
    private var scale: JournalSummaryScale = .days
    private var contentRevision = 0
    private var emptyTransitionDay = TimelineDayKey.today()
    private var callbacks: Callbacks?
    private var pendingScrollRequest: HomeFeedScrollRequest?
    private var animatedScrollRequestID: UUID?
    private var appliedScrollRequestIDs: Set<UUID> = []
    private var enrichmentTasks: [ItemID: Task<Void, Never>] = [:]
    private var prefetchTasks: [ItemID: Task<Void, Never>] = [:]
    private var displayedItems: [ObjectIdentifier: ItemID] = [:]
    private var isScrolling = false
    private var lastReportedAnchor: HomeFeedAnchor?
    private var lastLayoutWidth: CGFloat = 0

    private lazy var dayRegistration = UICollectionView.CellRegistration<
        UIKitDaySummaryCell,
        TimelineDayKey
    > { [weak self] cell, _, day in
        self?.configure(cell, for: day)
    }

    private lazy var periodRegistration = UICollectionView.CellRegistration<
        UIKitPeriodSummaryCell,
        PeriodSummaryKey
    > { [weak self] cell, _, period in
        self?.configure(cell, for: period)
    }

    private lazy var statusRegistration = UICollectionView.CellRegistration<
        UIKitHomeFeedStatusCell,
        ItemID
    > { [weak self] cell, _, item in
        switch item {
        case .empty:
            cell.configure(
                symbol: "book.closed",
                title: String(localized: "No Journal Days"),
                message: String(localized: "Create your first entry in today’s timeline."),
                actionTitle: String(localized: "Start Today"),
                action: { [weak self] in self?.openEmptyTimeline() }
            )
        case .error(let message):
            cell.configure(
                symbol: "exclamationmark.triangle",
                title: String(localized: "Couldn’t Load Journal"),
                message: message,
                actionTitle: nil,
                action: nil
            )
        case .day, .period:
            break
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground
        layout.scrollDirection = .vertical
        layout.sectionInsetReference = .fromSafeArea

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.topEdgeEffect.style = .soft
        collectionView.bottomEdgeEffect.style = .soft
        collectionView.topEdgeEffect.isHidden = false
        collectionView.bottomEdgeEffect.isHidden = false
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (controller: HomeFeedViewController, _) in
            controller.layout.invalidateLayout()
            controller.collectionView.collectionViewLayout.invalidateLayout()
        }
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // UIKit requires registrations to exist before entering the cell
        // provider. Force the lazy properties now so their handlers can still
        // capture this controller weakly without being created per dequeue.
        _ = dayRegistration
        _ = periodRegistration
        _ = statusRegistration
        dataSource = UICollectionViewDiffableDataSource<Int, ItemID>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, item in
            guard let self else { return nil }
            switch item {
            case .day(let day):
                return collectionView.dequeueConfiguredReusableCell(
                    using: dayRegistration,
                    for: indexPath,
                    item: day
                )
            case .period(let period):
                return collectionView.dequeueConfiguredReusableCell(
                    using: periodRegistration,
                    for: indexPath,
                    item: period
                )
            case .empty, .error:
                return collectionView.dequeueConfiguredReusableCell(
                    using: statusRegistration,
                    for: indexPath,
                    item: item
                )
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = collectionView.bounds.width
        guard abs(width - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = width
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
        performPendingScrollRequestIfPossible()
    }

    func update(
        modelContext: ModelContext,
        dayRows: [DaySummaryRowModel],
        monthRows: [PeriodSummaryRowModel],
        yearRows: [PeriodSummaryRowModel],
        errorMessage: String?,
        scale: JournalSummaryScale,
        contentRevision: Int,
        emptyTransitionDay: TimelineDayKey,
        scrollRequest: HomeFeedScrollRequest?,
        callbacks: Callbacks
    ) {
        loadViewIfNeeded()
        self.callbacks = callbacks
        self.contentRevision = contentRevision
        self.emptyTransitionDay = emptyTransitionDay
        self.modelContext = modelContext
        self.dayRows = Dictionary(uniqueKeysWithValues: dayRows.map { ($0.id, $0) })
        self.periodRows = Dictionary(
            uniqueKeysWithValues: (monthRows + yearRows).map { ($0.id, $0) }
        )
        let scaleChanged = self.scale != scale
        self.scale = scale
        if scaleChanged {
            lastReportedAnchor = nil
            cancelAllLoading()
            layout.invalidateLayout()
        }

        if let scrollRequest,
           !appliedScrollRequestIDs.contains(scrollRequest.id) {
            pendingScrollRequest = scrollRequest
        } else if scrollRequest == nil {
            pendingScrollRequest = nil
        }

        let items: [ItemID]
        switch scale {
        case .days:
            if let errorMessage {
                items = [.error(errorMessage)]
            } else if dayRows.isEmpty {
                items = [.empty(emptyTransitionDay)]
            } else {
                items = dayRows.map { .day($0.id) }
            }
        case .months:
            items = monthRows.map { .period($0.id) }
        case .years:
            items = yearRows.map { .period($0.id) }
        }

        let existing = dataSource.snapshot().itemIdentifiers
        guard existing != items else {
            UIView.performWithoutAnimation {
                layout.invalidateLayout()
                reconfigureVisibleCells()
                collectionView.layoutIfNeeded()
                performPendingScrollRequestIfPossible()
            }
            return
        }

        var snapshot = NSDiffableDataSourceSnapshot<Int, ItemID>()
        snapshot.appendSections([0])
        snapshot.appendItems(items)
        let completion = { [weak self] in
            guard let self else { return }
            UIView.performWithoutAnimation {
                self.collectionView.collectionViewLayout.invalidateLayout()
                self.collectionView.layoutIfNeeded()
                self.performPendingScrollRequestIfPossible()
                self.reportVisibleAnchor()
            }
        }
        if scaleChanged {
            UIView.performWithoutAnimation {
                dataSource.applySnapshotUsingReloadData(
                    snapshot,
                    completion: completion
                )
            }
        } else {
            UIView.performWithoutAnimation {
                dataSource.apply(
                    snapshot,
                    animatingDifferences: false,
                    completion: completion
                )
            }
        }
    }

    private func configure(
        _ cell: UIKitDaySummaryCell,
        for day: TimelineDayKey
    ) {
        guard let row = dayRows[day] else { return }
        cell.configure(model: row, loadsDeferredContent: true)
    }

    private func configure(
        _ cell: UIKitPeriodSummaryCell,
        for key: PeriodSummaryKey
    ) {
        guard let row = periodRows[key] else { return }
        cell.configure(
            model: row,
            loadsDeferredContent: true,
            onOpenDay: { [weak self] day in
                self?.presentTimeline(day, source: .period(key))
            }
        )
    }

    private func reconfigureVisibleCells() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let item = dataSource.itemIdentifier(for: indexPath) else { continue }
            switch (item, collectionView.cellForItem(at: indexPath)) {
            case let (.day(day), cell as UIKitDaySummaryCell):
                configure(cell, for: day)
            case let (.period(period), cell as UIKitPeriodSummaryCell):
                configure(cell, for: period)
            default:
                break
            }
        }
    }

    private func performPendingScrollRequestIfPossible() {
        guard isViewLoaded,
              view.window != nil,
              let request = pendingScrollRequest,
              request.scale == scale,
              let item = itemID(for: request.anchor),
              let indexPath = dataSource.indexPath(for: item) else { return }

        collectionView.layoutIfNeeded()
        pendingScrollRequest = nil
        if request.animated {
            animatedScrollRequestID = request.id
            setScrolling(true)
            collectionView.scrollToItem(
                at: indexPath,
                at: request.alignment == .top ? .top : .bottom,
                animated: true
            )
        } else {
            UIView.performWithoutAnimation {
                collectionView.scrollToItem(
                    at: indexPath,
                    at: request.alignment == .top ? .top : .bottom,
                    animated: false
                )
                collectionView.layoutIfNeeded()
            }
            finishScrollRequest(request.id)
            reportVisibleAnchor()
        }
    }

    private func finishScrollRequest(_ id: UUID) {
        appliedScrollRequestIDs.insert(id)
        callbacks?.onScrollRequestApplied(id)
    }

    private func itemID(for anchor: HomeFeedAnchor) -> ItemID? {
        switch anchor {
        case .day(let day): .day(day)
        case .period(let period): .period(period)
        }
    }

    private func openEmptyTimeline() {
        presentTimeline(
            emptyTransitionDay,
            source: .empty(emptyTransitionDay)
        )
    }

    private func presentTimeline(
        _ day: TimelineDayKey,
        source: HomeTransitionSource
    ) {
        guard presentedViewController == nil, let modelContext else { return }
        let root = UIKitTimelinePresentationRoot(
            initialDay: day,
            contentRevision: contentRevision,
            modelContext: modelContext,
            onDayChange: { [weak self] day in
                guard let self else { return }
                guard let hosting = presentedViewController
                    as? UIKitTimelineTransitionSourceProviding else { return }
                hosting.transitionSource = callbacks?.onTimelineDayChange(day)
                    ?? .day(day)
            }
        )
        let hosting = UIKitTimelineHostingController(rootView: root)
        hosting.transitionSource = source
        hosting.preferredTransition = .zoom { [weak self] context in
            guard let source = (
                context.zoomedViewController
                    as? UIKitTimelineTransitionSourceProviding
            )?.transitionSource else { return nil }
            return self?.transitionSourceView(for: source)
        }
        hosting.onDismiss = { [weak self] in
            self?.callbacks?.onTimelineDismiss()
        }
        present(hosting, animated: true)
    }

    private func transitionSourceView(
        for source: HomeTransitionSource
    ) -> UIView? {
        let item: ItemID? = switch source {
        case .day(let day): .day(day)
        case .period(let period): .period(period)
        case .empty(let day): .empty(day)
        case .today, .search: nil
        }
        guard let item,
              let indexPath = dataSource.indexPath(for: item) else { return nil }
        return collectionView.cellForItem(at: indexPath)
    }

    private var contentWidth: CGFloat {
        min(440, max(0, collectionView.bounds.width - 32))
    }

    private func reportVisibleAnchor() {
        let visibleRect = CGRect(
            origin: collectionView.contentOffset,
            size: collectionView.bounds.size
        )
        let threshold: CGFloat = scale == .days ? 0.1 : 0.2
        let attributes = collectionView.collectionViewLayout
            .layoutAttributesForElements(in: visibleRect)?
            .filter { $0.representedElementCategory == .cell }
            .sorted { $0.frame.minY < $1.frame.minY } ?? []

        let anchor = attributes.compactMap { attributes -> HomeFeedAnchor? in
            guard attributes.frame.height > 0,
                  visibleRect.intersection(attributes.frame).height
                    / attributes.frame.height >= threshold,
                  let item = dataSource.itemIdentifier(for: attributes.indexPath)
            else { return nil }
            return item.anchor
        }.first

        guard let anchor, anchor != lastReportedAnchor else { return }
        lastReportedAnchor = anchor
        callbacks?.onVisibleAnchorChange(scale, anchor)
    }

    private func setScrolling(_ value: Bool) {
        guard isScrolling != value else { return }
        isScrolling = value
        if value {
            enrichmentTasks.values.forEach { $0.cancel() }
            enrichmentTasks.removeAll()
        }
        reconfigureVisibleCells()
        if !value {
            for indexPath in collectionView.indexPathsForVisibleItems {
                scheduleEnrichment(at: indexPath)
            }
        }
    }

    private func scheduleEnrichment(at indexPath: IndexPath) {
        guard !isScrolling,
              let item = dataSource.itemIdentifier(for: indexPath),
              enrichmentTasks[item] == nil else { return }
        let task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            switch item {
            case .day(let day):
                await dayRows[day]?.loadEnrichment()
            case .period(let period):
                await periodRows[period]?.loadEnrichment()
            case .empty, .error:
                break
            }
            guard !Task.isCancelled else { return }
            enrichmentTasks[item] = nil
            guard let currentIndexPath = dataSource.indexPath(for: item) else { return }
            switch (item, collectionView.cellForItem(at: currentIndexPath)) {
            case let (.day(day), cell as UIKitDaySummaryCell):
                configure(cell, for: day)
            case let (.period(period), cell as UIKitPeriodSummaryCell):
                configure(cell, for: period)
            default:
                break
            }
        }
        enrichmentTasks[item] = task
    }

    private func startPrefetching(_ item: ItemID) {
        guard prefetchTasks[item] == nil else { return }
        let width = contentWidth
        let scale = traitCollection.displayScale
        let appearance: SummaryMapSnapshotRequest.Appearance =
            traitCollection.userInterfaceStyle == .dark ? .dark : .light
        prefetchTasks[item] = Task { [weak self] in
            guard let self else { return }
            switch item {
            case .day(let day):
                guard let row = dayRows[day] else { return }
                await row.loadMapEnrichment()
                guard !Task.isCancelled else { return }
                await UIKitHomeFeedAssetPrefetcher.prefetch(
                    day: row,
                    contentWidth: width,
                    displayScale: scale,
                    appearance: appearance
                )
            case .period(let period):
                guard let row = periodRows[period] else { return }
                await row.loadEnrichment()
                guard !Task.isCancelled else { return }
                await UIKitHomeFeedAssetPrefetcher.prefetch(
                    period: row,
                    contentWidth: width,
                    displayScale: scale,
                    appearance: appearance
                )
            case .empty, .error:
                break
            }
            prefetchTasks[item] = nil
            guard let currentIndexPath = dataSource.indexPath(for: item) else {
                return
            }
            switch (item, collectionView.cellForItem(at: currentIndexPath)) {
            case let (.day(day), cell as UIKitDaySummaryCell):
                configure(cell, for: day)
            case let (.period(period), cell as UIKitPeriodSummaryCell):
                configure(cell, for: period)
            default:
                break
            }
        }
    }

    private func cancelAllLoading() {
        enrichmentTasks.values.forEach { $0.cancel() }
        prefetchTasks.values.forEach { $0.cancel() }
        enrichmentTasks.removeAll()
        prefetchTasks.removeAll()
    }
}

extension HomeFeedViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = contentWidth
        guard let item = dataSource.itemIdentifier(for: indexPath) else {
            return CGSize(width: width, height: 1)
        }
        let height: CGFloat
        switch item {
        case .day(let day):
            height = dayRows[day].map {
                UIKitDaySummaryCell.height(for: $0, width: width)
            } ?? 1
        case .period(let period):
            height = periodRows[period].map {
                UIKitPeriodSummaryCell.height(for: $0, width: width)
            } ?? 1
        case .empty, .error:
            height = 360
        }
        return CGSize(width: width, height: height)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        insetForSectionAt section: Int
    ) -> UIEdgeInsets {
        let horizontal = max(16, (collectionView.bounds.width - 440) / 2)
        return UIEdgeInsets(top: 16, left: horizontal, bottom: 16, right: horizontal)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumLineSpacingForSectionAt section: Int
    ) -> CGFloat {
        scale == .days ? 32 : 34
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .day(let day):
            presentTimeline(day, source: .day(day))
        case .period(let key):
            if let summary = periodRows[key]?.summary {
                callbacks?.onOpenPeriod(summary)
            }
        case .empty, .error:
            break
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        displayedItems[ObjectIdentifier(cell)] = item
        startPrefetching(item)
        switch (item, cell) {
        case let (.day(day), cell as UIKitDaySummaryCell):
            configure(cell, for: day)
        case let (.period(period), cell as UIKitPeriodSummaryCell):
            configure(cell, for: period)
        default:
            break
        }
        scheduleEnrichment(at: indexPath)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        if let item = displayedItems.removeValue(forKey: ObjectIdentifier(cell)) {
            enrichmentTasks[item]?.cancel()
            enrichmentTasks[item] = nil
        }
        (cell as? UIKitDaySummaryCell)?.didEndDisplaying()
        (cell as? UIKitPeriodSummaryCell)?.didEndDisplaying()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        pendingScrollRequest = nil
        animatedScrollRequestID = nil
        callbacks?.onUserScroll()
        setScrolling(true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        reportVisibleAnchor()
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        if !decelerate { setScrolling(false) }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        setScrolling(false)
        reportVisibleAnchor()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        setScrolling(false)
        if let id = animatedScrollRequestID {
            animatedScrollRequestID = nil
            finishScrollRequest(id)
        }
        reportVisibleAnchor()
    }
}

@MainActor
private protocol UIKitTimelineTransitionSourceProviding: AnyObject {
    var transitionSource: HomeTransitionSource { get set }
}

@MainActor
private final class UIKitTimelineHostingController<Content: View>:
    UIHostingController<Content>, UIKitTimelineTransitionSourceProviding {
    var onDismiss: (() -> Void)?
    var transitionSource: HomeTransitionSource = .today
    private var didNotifyDismissal = false

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard !didNotifyDismissal,
              isBeingDismissed || presentingViewController == nil else { return }
        didNotifyDismissal = true
        onDismiss?()
    }
}

private struct UIKitTimelinePresentationRoot: View {
    @State private var selectedDay: TimelineDayKey
    let contentRevision: Int
    let modelContext: ModelContext
    let onDayChange: (TimelineDayKey) -> Void

    init(
        initialDay: TimelineDayKey,
        contentRevision: Int,
        modelContext: ModelContext,
        onDayChange: @escaping (TimelineDayKey) -> Void
    ) {
        _selectedDay = State(initialValue: initialDay)
        self.contentRevision = contentRevision
        self.modelContext = modelContext
        self.onDayChange = onDayChange
    }

    var body: some View {
        NavigationStack {
            DayTimelineScreen(
                selectedDay: $selectedDay,
                contentRevision: contentRevision
            )
        }
        .modelContext(modelContext)
        .onChange(of: selectedDay) { _, day in
            onDayChange(day)
        }
    }
}

extension HomeFeedViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        for indexPath in indexPaths {
            guard let item = dataSource.itemIdentifier(for: indexPath) else { continue }
            startPrefetching(item)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cancelPrefetchingForItemsAt indexPaths: [IndexPath]
    ) {
        for indexPath in indexPaths {
            guard let item = dataSource.itemIdentifier(for: indexPath) else { continue }
            prefetchTasks[item]?.cancel()
            prefetchTasks[item] = nil
        }
    }
}
