import Foundation
import SwiftData
import SwiftUI
import UIKit

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
    let preservesZoomViewport: Bool

    init(
        scale: JournalSummaryScale,
        anchor: HomeFeedAnchor,
        alignment: HomeFeedScrollAlignment,
        animated: Bool = false,
        preservesZoomViewport: Bool = false
    ) {
        self.scale = scale
        self.anchor = anchor
        self.alignment = alignment
        self.animated = animated
        self.preservesZoomViewport = preservesZoomViewport
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
    @State private var isFeedScrolling = false
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
                onScrollStateChange: { isFeedScrolling = $0 },
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
                isEnabled: isFeedPositioned && !isFeedScrolling,
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
        let preservesZoomViewport = pendingScaleTarget == nil
        let target = pendingScaleTarget
            ?? inferredTarget(from: scale, to: newScale)
        pendingScaleTarget = nil
        let request = target.map {
            HomeFeedScrollRequest(
                scale: newScale,
                anchor: $0,
                alignment: .top,
                preservesZoomViewport: preservesZoomViewport
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
            let rememberedDay = visibleDay.flatMap { day in
                MonthKey(day: day) == visibleMonth ? day : nil
            }
            let day = rememberedDay ?? visibleMonth.flatMap(model.firstDay) ?? model.days.last
            return day.map(HomeFeedAnchor.day)
        case (.months, .years):
            let year = visibleMonth.map { YearKey(year: $0.year) }
                ?? model.yearRows.last?.summary.yearKey
            return year.map { .period(.year($0)) }
        case (.years, .days):
            let rememberedDay = visibleDay.flatMap { day in
                day.year == visibleYear?.year ? day : nil
            }
            let day = rememberedDay ?? visibleYear.flatMap { model.firstMonth(in: $0) }
                .flatMap(model.firstDay) ?? model.days.last
            return day.map(HomeFeedAnchor.day)
        case (.years, .months):
            let rememberedMonth = visibleMonth.flatMap { month in
                month.year == visibleYear?.year ? month : nil
            }
            let month = rememberedMonth ?? visibleYear.flatMap(model.firstMonth)
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
        scrollRequest = nil
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
