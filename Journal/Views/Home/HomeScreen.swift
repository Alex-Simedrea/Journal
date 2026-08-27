import Foundation
import SwiftData
import SwiftUI
import UIKit

@MainActor
@Observable
private final class HomeFeedDeferredLoadingPolicy {
    private(set) var allowsLoading = true

    @ObservationIgnored
    private var phase: ScrollPhase = .idle

    func phaseDidChange(
        to newPhase: ScrollPhase
    ) {
        phase = newPhase
        allowsLoading = newPhase == .idle
    }
}

enum HomeTransitionSource: Hashable {
    case day(TimelineDayKey)
    case period(PeriodSummaryKey)
    case today
    case search
    case empty(TimelineDayKey)
}

private struct PresentedTimeline: Identifiable {
    let selectedDay: TimelineDayKey
    let source: HomeTransitionSource

    var id: TimelineDayKey { selectedDay }
}

enum HomeFeedAnchor: Hashable {
    case day(TimelineDayKey)
    case period(PeriodSummaryKey)
}

enum HomeFeedScrollAlignment: Hashable {
    case top
    case bottom
}

struct HomeFeedScrollRequest: Hashable {
    let id = UUID()
    let scale: JournalSummaryScale
    let anchor: HomeFeedAnchor
    let alignment: HomeFeedScrollAlignment
    let animated: Bool

    init(
        scale: JournalSummaryScale,
        anchor: HomeFeedAnchor,
        alignment: HomeFeedScrollAlignment,
        animated: Bool = false
    ) {
        self.scale = scale
        self.anchor = anchor
        self.alignment = alignment
        self.animated = animated
    }
}

struct HomeScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var timelineTransition
    @State private var model = HomeFeedModel()
    @State private var selectedScale: JournalSummaryScale = .days
    @State private var scale: JournalSummaryScale = .days
    @State private var scrollPosition: HomeFeedAnchor?
    @State private var scrollRequest: HomeFeedScrollRequest?
    @State private var pendingScaleTarget: HomeFeedAnchor?
    @State private var visibleDay: TimelineDayKey?
    @State private var visibleMonth: MonthKey?
    @State private var visibleYear: YearKey?
    @State private var isFeedReady = false
    @State private var isFeedPositioned = false
    @State private var didReportInitialFeedReady = false
    @State private var emptyTransitionDay = TimelineDayKey.today()
    @State private var presentedTimeline: PresentedTimeline?
    @State private var isCalendarPresented = false
    @State private var isProfilePresented = false
    @State private var isSearchPresented = false
    let contentRevision: Int
    let onInitialFeedReady: () -> Void

    init(
        contentRevision: Int = 0,
        onInitialFeedReady: @escaping () -> Void = {}
    ) {
        self.contentRevision = contentRevision
        self.onInitialFeedReady = onInitialFeedReady
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if isFeedReady {
                    feed
                } else {
                    Color(uiColor: .systemGroupedBackground)
                }
            }
            .navigationTitle(navigationTitle)
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                topToolbar
                HomeBottomToolbar(
                    scale: $selectedScale,
                    namespace: timelineTransition,
                    onToday: {
                        let today = TimelineDayKey.today()
                        presentTimeline(today, source: .today)
                    },
                    onScaleReselected: scrollToBottom,
                    onSearch: { isSearchPresented = true }
                )
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .sheet(isPresented: $isCalendarPresented) {
            TimelineCalendarSheet(selectedDay: calendarDay) { selectedDay in
                handleCalendarSelection(selectedDay)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isProfilePresented, onDismiss: {
            Task { await reloadFeed() }
        }) {
            ProfileMenuSheet()
        }
        .fullScreenCover(
            item: $presentedTimeline,
            onDismiss: timelineDidDismiss
        ) { session in
            TimelineFullScreenCover(
                initialDay: session.selectedDay,
                initialSource: session.source,
                contentRevision: contentRevision,
                namespace: timelineTransition,
                onDayChange: timelineDayDidChange
            )
        }
        .fullScreenCover(isPresented: $isSearchPresented) {
            NavigationStack {
                EntrySearchScreen()
            }
            .navigationTransition(
                .zoom(
                    sourceID: HomeTransitionSource.search,
                    in: timelineTransition
                )
            )
        }
        .task(id: contentRevision) {
            await reloadFeed()
            guard !Task.isCancelled else { return }
            if !isFeedReady {
                prepareInitialFeedPosition()
            }
            isFeedReady = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await reloadFeed() }
            }
        }
        .onChange(of: selectedScale) { oldScale, newScale in
            prepareScaleSwitch(from: oldScale, to: newScale)
        }
        .onReceive(TimelineDataChange.publisher) { _ in
            Task { await reloadFeed() }
        }
        .task(id: selectedScale) {
            guard selectedScale != .days else { return }
            await model.loadPeriodPhotoMetadata()
        }
    }

    private var feed: some View {
        GeometryReader { proxy in
            UIKitHomeFeed(
                modelContext: modelContext,
                model: model,
                scale: scale,
                contentRevision: contentRevision,
                emptyTransitionDay: emptyTransitionDay,
                scrollRequest: scrollRequest,
                onVisibleAnchorChange: updateVisibleAnchor,
                onScrollRequestApplied: scrollRequestDidApply,
                onUserScroll: userDidScrollFeed,
                onOpenDay: {
                    presentTimeline($0, source: .day($0))
                },
                onOpenPeriod: openPeriod,
                onOpenPeriodDay: { day, period in
                    presentTimeline(day, source: .period(period))
                },
                onStartToday: {
                    let today = TimelineDayKey.today()
                    emptyTransitionDay = today
                    presentTimeline(today, source: .empty(today))
                },
                onTimelineDayChange: timelineDayDidChange,
                onTimelineDismiss: timelineDidDismiss
            )
            .modifier(HomeFeedPrewarmingModifier(
                model: model,
                isEnabled: isFeedPositioned,
                contentWidth: min(440, max(0, proxy.size.width - 32))
            ))
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .opacity(isFeedPositioned ? 1 : 0)
        .allowsHitTesting(isFeedPositioned)
    }

    @ToolbarContentBuilder private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isCalendarPresented = true
            } label: {
                Label("Choose date", systemImage: "calendar")
            }
        }

        ToolbarSpacer(.fixed, placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isProfilePresented = true
            } label: {
                Label("Profile", systemImage: "person.fill")
            }
        }
    }

    private var calendarDay: TimelineDayKey {
        visibleDay
            ?? visibleMonth.flatMap { model.firstDay(in: $0) }
            ?? visibleYear.flatMap { year in
                model.firstMonth(in: year).flatMap(model.firstDay)
            }
            ?? model.days.last
            ?? .today()
    }

    private var navigationTitle: String {
        switch scale {
        case .days:
            DaySummaryDatePresentation.monthTitle(
                for: visibleDay ?? model.days.last ?? .today()
            )
        case .months:
            String((visibleMonth ?? model.monthRows.last?.summary.monthKey)?.year
                ?? Calendar.current.component(.year, from: .now))
        case .years:
            String(localized: "Years")
        }
    }

    private func reloadFeed() async {
        await model.reload(in: modelContext)
    }

    private func prepareInitialFeedPosition() {
        guard let day = model.days.last else {
            markFeedPositioned()
            return
        }
        setVisibleAnchor(.day(day))
        scrollRequest = HomeFeedScrollRequest(
            scale: .days,
            anchor: .day(day),
            alignment: .bottom
        )
    }

    private func prepareScaleSwitch(
        from _: JournalSummaryScale,
        to newScale: JournalSummaryScale
    ) {
        guard scale != newScale else { return }
        let target = pendingScaleTarget
            ?? inferredTarget(from: scale, to: newScale)
        pendingScaleTarget = nil
        let request = target.map {
            HomeFeedScrollRequest(
                scale: newScale,
                anchor: $0,
                alignment: .top
            )
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let target {
                setVisibleAnchor(target)
            }
            scrollPosition = target
            scrollRequest = request
            scale = newScale
        }
    }

    private func scrollToBottom(of selectedScale: JournalSummaryScale) {
        guard selectedScale == scale else { return }

        switch selectedScale {
        case .days:
            guard let day = model.days.last else { return }
            setVisibleAnchor(.day(day))
            scrollRequest = HomeFeedScrollRequest(
                scale: .days,
                anchor: .day(day),
                alignment: .bottom,
                animated: true
            )
        case .months:
            guard let key = model.monthRows.last?.id else { return }
            setVisibleAnchor(.period(key))
            scrollRequest = HomeFeedScrollRequest(
                scale: .months,
                anchor: .period(key),
                alignment: .bottom,
                animated: true
            )
        case .years:
            guard let key = model.yearRows.last?.id else { return }
            setVisibleAnchor(.period(key))
            scrollRequest = HomeFeedScrollRequest(
                scale: .years,
                anchor: .period(key),
                alignment: .bottom,
                animated: true
            )
        }
    }

    private func inferredTarget(
        from oldScale: JournalSummaryScale,
        to newScale: JournalSummaryScale
    ) -> HomeFeedAnchor? {
        switch (oldScale, newScale) {
        case (.days, .months):
            let month = visibleDay.map(MonthKey.init)
                ?? model.monthRows.last?.summary.monthKey
            return month.map { .period(.month($0)) }
        case (.days, .years):
            let year = visibleDay.map { YearKey(year: $0.year) }
                ?? model.yearRows.last?.summary.yearKey
            return year.map { .period(.year($0)) }
        case (.months, .days):
            let day = visibleMonth.flatMap(model.firstDay) ?? model.days.last
            return day.map(HomeFeedAnchor.day)
        case (.months, .years):
            let year = visibleMonth.map { YearKey(year: $0.year) }
                ?? model.yearRows.last?.summary.yearKey
            return year.map { .period(.year($0)) }
        case (.years, .days):
            let day = visibleYear.flatMap { model.firstMonth(in: $0) }
                .flatMap(model.firstDay) ?? model.days.last
            return day.map(HomeFeedAnchor.day)
        case (.years, .months):
            let month = visibleYear.flatMap(model.firstMonth)
                ?? model.monthRows.last?.summary.monthKey
            return month.map { .period(.month($0)) }
        default:
            return nil
        }
    }

    private func updateVisibleAnchor(
        _ reportedScale: JournalSummaryScale,
        _ anchor: HomeFeedAnchor
    ) {
        guard reportedScale == scale else { return }
        if let scrollRequest,
           scrollRequest.scale == reportedScale,
           scrollRequest.anchor != anchor {
            return
        }

        switch (reportedScale, anchor) {
        case (.days, .day(_)),
             (.months, .period(.month(_))),
             (.years, .period(.year(_))):
            setVisibleAnchor(anchor)
        default:
            break
        }
    }

    private func setVisibleAnchor(_ anchor: HomeFeedAnchor) {
        switch anchor {
        case .day(let day):
            visibleDay = day
        case .period(.month(let month)):
            visibleMonth = month
            visibleYear = YearKey(year: month.year)
        case .period(.year(let year)):
            visibleYear = year
        }
    }

    private func userDidScrollFeed() {
        scrollRequest = nil
    }

    private func scrollRequestDidApply(_ requestID: UUID) {
        guard scrollRequest?.id == requestID else { return }
        markFeedPositioned()
    }

    private func markFeedPositioned() {
        isFeedPositioned = true
        guard !didReportInitialFeedReady else { return }
        didReportInitialFeedReady = true
        onInitialFeedReady()
    }

    private func handleCalendarSelection(_ selectedDay: TimelineDayKey) {
        isCalendarPresented = false
        guard let target = model.nearestDay(to: selectedDay) else {
            emptyTransitionDay = selectedDay
            presentTimeline(selectedDay, source: .empty(selectedDay))
            return
        }
        visibleDay = target
        if scale == .days {
            scrollPosition = .day(target)
            scrollRequest = HomeFeedScrollRequest(
                scale: .days,
                anchor: .day(target),
                alignment: .top
            )
        } else {
            pendingScaleTarget = .day(target)
            selectedScale = .days
        }
    }

    private func openPeriod(_ summary: PeriodSummary) {
        switch summary.key {
        case .year(let year):
            guard let month = model.firstMonth(in: year) else { return }
            visibleMonth = month
            if scale == .months {
                scrollPosition = .period(.month(month))
                scrollRequest = HomeFeedScrollRequest(
                    scale: .months,
                    anchor: .period(.month(month)),
                    alignment: .top
                )
            } else {
                pendingScaleTarget = .period(.month(month))
                selectedScale = .months
            }
        case .month(let month):
            openMonth(month)
        }
    }

    private func openMonth(_ month: MonthKey) {
        guard let day = model.firstDay(in: month) else { return }
        visibleDay = day
        if scale == .days {
            scrollPosition = .day(day)
            scrollRequest = HomeFeedScrollRequest(
                scale: .days,
                anchor: .day(day),
                alignment: .top
            )
        } else {
            pendingScaleTarget = .day(day)
            selectedScale = .days
        }
    }

    private func presentTimeline(
        _ selectedDay: TimelineDayKey,
        source: HomeTransitionSource
    ) {
        presentedTimeline = PresentedTimeline(
            selectedDay: selectedDay,
            source: source
        )
    }

    private func timelineDayDidChange(
        _ selectedDay: TimelineDayKey
    ) -> HomeTransitionSource {
        guard let nearest = model.nearestDay(to: selectedDay) else {
            emptyTransitionDay = selectedDay
            return .empty(selectedDay)
        }
        switch scale {
        case .days:
            return .day(nearest)
        case .months:
            return .period(.month(MonthKey(day: nearest)))
        case .years:
            return .period(.year(YearKey(year: nearest.year)))
        }
    }

    private func timelineDidDismiss() {
        Task { await reloadFeed() }
    }
}

struct HomeBottomToolbar: ToolbarContent {
    @Binding var scale: JournalSummaryScale
    let namespace: Namespace.ID
    let onToday: () -> Void
    let onScaleReselected: (JournalSummaryScale) -> Void
    let onSearch: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Button(action: onToday) {
                Label("Today", systemImage: "text.rectangle.page")
            }
            .matchedTransitionSource(
                id: HomeTransitionSource.today,
                in: namespace
            )
        }

        ToolbarSpacer(.flexible, placement: .bottomBar)

        ToolbarItem(placement: .bottomBar) {
            HomeScalePicker(
                scale: $scale,
                onReselect: onScaleReselected
            )
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.flexible, placement: .bottomBar)

        ToolbarItem(placement: .bottomBar) {
            Button(action: onSearch) {
                Label("Search", systemImage: "magnifyingglass")
            }
            .matchedTransitionSource(
                id: HomeTransitionSource.search,
                in: namespace
            )
            .accessibilityHint("Search journal entries")
        }
    }
}

private struct HomeScalePicker: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @Binding var scale: JournalSummaryScale
    let onReselect: (JournalSummaryScale) -> Void

    var body: some View {
        Picker("Summary scale", selection: $scale) {
            ForEach(JournalSummaryScale.allCases) { scale in
                Text(scale.title)
                    .tag(scale)
            }
        }
        .pickerStyle(.segmented)
        .gesture(
            HomeScaleReselectGesture(
                selectedScale: scale,
                layoutDirection: layoutDirection,
                onReselect: onReselect
            )
        )
        .accessibilityAction(named: "Scroll to Latest") {
            onReselect(scale)
        }
    }
}

private struct HomeScaleReselectGesture: UIGestureRecognizerRepresentable {
    let selectedScale: JournalSummaryScale
    let layoutDirection: LayoutDirection
    let onReselect: (JournalSummaryScale) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(onReselect: onReselect)
    }

    func makeUIGestureRecognizer(context: Context) -> ReselectRecognizer {
        let recognizer = ReselectRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(
        _ recognizer: ReselectRecognizer,
        context: Context
    ) {
        recognizer.currentSelection = selectedScale
        context.coordinator.onReselect = onReselect
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: ReselectRecognizer,
        context: Context
    ) {
        guard recognizer.state == .ended,
              let originalSelection = recognizer.selectionAtTouchStart,
              let view = recognizer.view,
              view.bounds.width > 0 else { return }

        let scales = JournalSummaryScale.allCases
        let location = recognizer.location(in: view)
        let rawIndex = min(
            scales.count - 1,
            max(0, Int(location.x / view.bounds.width * CGFloat(scales.count)))
        )
        let index = layoutDirection == .rightToLeft
            ? scales.count - 1 - rawIndex
            : rawIndex
        let tappedScale = scales[index]

        guard tappedScale == originalSelection else { return }
        context.coordinator.onReselect(tappedScale)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onReselect: (JournalSummaryScale) -> Void

        init(onReselect: @escaping (JournalSummaryScale) -> Void) {
            self.onReselect = onReselect
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    final class ReselectRecognizer: UITapGestureRecognizer {
        var currentSelection: JournalSummaryScale = .days
        private(set) var selectionAtTouchStart: JournalSummaryScale?

        override func touchesBegan(
            _ touches: Set<UITouch>,
            with event: UIEvent
        ) {
            selectionAtTouchStart = currentSelection
            super.touchesBegan(touches, with: event)
        }
    }
}

private struct HomeFeedPrewarmKey: Hashable {
    let revision: Int
    let pixelWidth: Int
    let appearance: SummaryMapSnapshotRequest.Appearance
}

private struct HomeFeedPrewarmingModifier: ViewModifier {
    let model: HomeFeedModel
    let isEnabled: Bool
    let contentWidth: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content.task(id: taskKey) {
            guard taskKey != nil else { return }
            // Visible cards load their own disk-cached snapshots. Prewarming
            // the surrounding browsing window is deliberately delayed so
            // MapKit and image decoding cannot monopolize the first frames.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await model.prewarmMapSnapshots(
                contentWidth: contentWidth,
                displayScale: displayScale,
                appearance: appearance
            )
        }
    }

    private var taskKey: HomeFeedPrewarmKey? {
        guard isEnabled, contentWidth > 1 else { return nil }
        return HomeFeedPrewarmKey(
            revision: model.mapSnapshotRevision,
            pixelWidth: Int((contentWidth * displayScale).rounded()),
            appearance: appearance
        )
    }

    private var appearance: SummaryMapSnapshotRequest.Appearance {
        colorScheme == .dark ? .dark : .light
    }
}

private struct HomeFeedContent: View {
    let model: HomeFeedModel
    let scale: JournalSummaryScale
    let namespace: Namespace.ID
    let emptyTransitionDay: TimelineDayKey
    let prewarmingEnabled: Bool
    @Binding var scrollPosition: HomeFeedAnchor?
    let scrollRequest: HomeFeedScrollRequest?
    let onVisibleAnchorChange: (JournalSummaryScale, HomeFeedAnchor) -> Void
    let onScrollRequestApplied: (UUID) -> Void
    let onUserScroll: () -> Void
    let onOpenDay: (TimelineDayKey) -> Void
    let onOpenPeriod: (PeriodSummary) -> Void
    let onOpenPeriodDay: (TimelineDayKey, PeriodSummaryKey) -> Void
    let onStartToday: () -> Void

    @State private var deferredLoading = HomeFeedDeferredLoadingPolicy()

    var body: some View {
        GeometryReader { container in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(
                        alignment: .leading,
                        spacing: scale == .days ? 32 : 34
                    ) {
                        switch scale {
                        case .days:
                            dayRows
                        case .months:
                            periodRows(model.monthRows)
                        case .years:
                            periodRows(model.yearRows)
                        }
                    }
                    .scrollTargetLayout()
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
                .defaultScrollAnchor(.bottom)
                .contentMargins(.bottom, 16, for: .scrollContent)
                .scrollPosition(id: $scrollPosition, anchor: .top)
                .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
                .onScrollTargetVisibilityChange(
                    idType: HomeFeedAnchor.self,
                    threshold: scale == .days ? 0.1 : 0.2
                ) { visible in
                    if let first = visible.first {
                        onVisibleAnchorChange(scale, first)
                    }
                }
                .onScrollPhaseChange { _, newPhase, context in
                    if newPhase == .interacting {
                        onUserScroll()
                    }
                    deferredLoading.phaseDidChange(to: newPhase)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .scrollContentBackground(.hidden)
                .task(id: scrollRequest?.id) {
                    guard let scrollRequest,
                          scrollRequest.scale == scale else { return }
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    jump(proxy, using: scrollRequest)
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    jump(proxy, using: scrollRequest)
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    onScrollRequestApplied(scrollRequest.id)
                }
            }
            .modifier(
                HomeFeedPrewarmingModifier(
                    model: model,
                    isEnabled: prewarmingEnabled
                        && deferredLoading.allowsLoading,
                    contentWidth: min(440, max(0, container.size.width - 32))
                )
            )
        }
    }

    @ViewBuilder
    private var dayRows: some View {
        if let errorMessage = model.errorMessage {
            HomeFeedErrorView(message: errorMessage)
        } else if model.rows.isEmpty {
            HomeFeedEmptyView(onStartToday: onStartToday)
                .matchedTransitionSource(
                    id: HomeTransitionSource.empty(emptyTransitionDay),
                    in: namespace
                )
        } else {
            ForEach(model.rows) { rowModel in
                HomeFeedDayRow(
                    model: rowModel,
                    namespace: namespace,
                    loadsDeferredContent: deferredLoading.allowsLoading,
                    onOpen: { onOpenDay(rowModel.id) }
                )
                .id(HomeFeedAnchor.day(rowModel.id))
            }
        }
    }

    @ViewBuilder
    private func periodRows(_ rows: [PeriodSummaryRowModel]) -> some View {
        ForEach(rows) { row in
            PeriodFeedRow(
                model: row,
                namespace: namespace,
                loadsDeferredContent: deferredLoading.allowsLoading,
                onOpen: { onOpenPeriod(row.summary) },
                onOpenDay: { onOpenPeriodDay($0, row.summary.key) }
            )
            .id(HomeFeedAnchor.period(row.id))
        }
    }

    private func jump(
        _ proxy: ScrollViewProxy,
        using request: HomeFeedScrollRequest
    ) {
        if request.animated {
            withAnimation(.smooth) {
                proxy.scrollTo(
                    request.anchor,
                    anchor: request.alignment == .top ? .top : .bottom
                )
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(
                request.anchor,
                anchor: request.alignment == .top ? .top : .bottom
            )
        }
    }
}

private struct HomeFeedDayRow: View {
    let model: DaySummaryRowModel
    let namespace: Namespace.ID
    let loadsDeferredContent: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                Text(DaySummaryDatePresentation.dayTitle(for: model.summary.day))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                DaySummaryCardContent(
                    model: model,
                    loadsDeferredContent: loadsDeferredContent
                )
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(
            id: HomeTransitionSource.day(model.id),
            in: namespace
        )
        .accessibilityHint("Opens this day’s timeline")
        .task(id: enrichmentTaskID) {
            guard loadsDeferredContent else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await model.loadEnrichment()
        }
    }

    private var enrichmentTaskID: DayEnrichmentTaskID {
        DayEnrichmentTaskID(
            loadsDeferredContent: loadsDeferredContent,
            revision: model.enrichmentRevision
        )
    }
}

private struct DayEnrichmentTaskID: Hashable {
    let loadsDeferredContent: Bool
    let revision: Int
}

private struct PeriodFeedRow: View {
    let model: PeriodSummaryRowModel
    let namespace: Namespace.ID
    let loadsDeferredContent: Bool
    let onOpen: () -> Void
    let onOpenDay: (TimelineDayKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.weight(.bold))
            PeriodSummaryCardContent(
                model: model,
                loadsDeferredContent: loadsDeferredContent,
                onOpenDay: onOpenDay
            )
        }
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
        .matchedTransitionSource(
            id: HomeTransitionSource.period(model.summary.key),
            in: namespace
        )
        .accessibilityHint("Opens the next level of this period")
        .task(id: loadsDeferredContent) {
            guard loadsDeferredContent else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await model.loadEnrichment()
        }
    }

    private var title: String {
        switch model.summary.key {
        case .month(let month): PeriodSummaryDatePresentation.title(for: month)
        case .year(let year): PeriodSummaryDatePresentation.title(for: year)
        }
    }
}

private struct HomeFeedEmptyView: View {
    let onStartToday: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Journal Days", systemImage: "book.closed")
        } description: {
            Text("Create your first entry in today’s timeline.")
        } actions: {
            Button("Start Today", action: onStartToday)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }
}

private struct HomeFeedErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t Load Journal", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }
}

private struct TimelineFullScreenCover: View {
    @State private var selectedDay: TimelineDayKey
    @State private var source: HomeTransitionSource
    let contentRevision: Int
    let namespace: Namespace.ID
    let onDayChange: (TimelineDayKey) -> HomeTransitionSource

    init(
        initialDay: TimelineDayKey,
        initialSource: HomeTransitionSource,
        contentRevision: Int,
        namespace: Namespace.ID,
        onDayChange: @escaping (TimelineDayKey) -> HomeTransitionSource
    ) {
        _selectedDay = State(initialValue: initialDay)
        _source = State(initialValue: initialSource)
        self.contentRevision = contentRevision
        self.namespace = namespace
        self.onDayChange = onDayChange
    }

    var body: some View {
        NavigationStack {
            DayTimelineScreen(
                selectedDay: $selectedDay,
                contentRevision: contentRevision
            )
        }
        .navigationTransition(.zoom(sourceID: source, in: namespace))
        .onChange(of: selectedDay) { _, day in
            source = onDayChange(day)
        }
    }
}

private struct ProfileMenuSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    LibraryScreen()
                } label: {
                    Label("Library", systemImage: "square.stack")
                }
                NavigationLink {
                    SettingsScreen()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .navigationTitle("Profile")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}
