import SwiftData
import SwiftUI

private struct PresentedTimeline: Identifiable {
    let selectedDay: TimelineDayKey
    let sourceDay: TimelineDayKey

    var id: TimelineDayKey { selectedDay }
}

private struct HomeFeedScrollRequest: Hashable {
    let id = UUID()
    let day: TimelineDayKey
}

struct HomeScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var dayTransition
    @State private var model = HomeFeedModel()
    @State private var scrollRequest: HomeFeedScrollRequest?
    @State private var visibleDay: TimelineDayKey?
    @State private var isFeedReady = false
    @State private var emptyTransitionDay = TimelineDayKey.today()
    @State private var presentedTimeline: PresentedTimeline?
    @State private var isCalendarPresented = false
    @State private var isProfilePresented = false
    let contentRevision: Int

    init(contentRevision: Int = 0) {
        self.contentRevision = contentRevision
    }

    private var titleDay: TimelineDayKey {
        visibleDay ?? scrollRequest?.day ?? .today()
    }

    var body: some View {
        Group {
            if isFeedReady {
                HomeFeedContent(
                    model: model,
                    namespace: dayTransition,
                    emptyTransitionDay: emptyTransitionDay,
                    scrollRequest: scrollRequest,
                    onVisibleDayChange: { visibleDay = $0 },
                    onOpenDay: presentTimeline,
                    onStartToday: {
                        let today = TimelineDayKey.today()
                        emptyTransitionDay = today
                        presentTimeline(today)
                    }
                )
            } else {
                Color(uiColor: .systemGroupedBackground)
            }
        }
        .navigationTitle(
            DaySummaryDatePresentation.monthTitle(for: titleDay)
        )
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
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
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $isCalendarPresented) {
            TimelineCalendarSheet(selectedDay: titleDay) { selectedDay in
                handleCalendarSelection(selectedDay)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isProfilePresented, onDismiss: {
            model.reload(in: modelContext)
        }) {
            ProfileMenuSheet()
        }
        .fullScreenCover(
            item: $presentedTimeline,
            onDismiss: timelineDidDismiss
        ) { session in
            TimelineFullScreenCover(
                initialDay: session.selectedDay,
                initialSourceDay: session.sourceDay,
                namespace: dayTransition,
                onDayChange: timelineDayDidChange
            )
        }
        .task(id: contentRevision) {
            reloadFeed()
            isFeedReady = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                reloadFeed()
            }
        }
    }

    private func reloadFeed() {
        model.reload(in: modelContext)
    }

    private func handleCalendarSelection(_ selectedDay: TimelineDayKey) {
        isCalendarPresented = false
        if let target = model.nearestDay(to: selectedDay) {
            scrollRequest = HomeFeedScrollRequest(day: target)
            visibleDay = target
        } else {
            emptyTransitionDay = selectedDay
            presentTimeline(selectedDay)
        }
    }

    private func presentTimeline(_ selectedDay: TimelineDayKey) {
        let sourceDay = model.nearestDay(to: selectedDay) ?? selectedDay
        presentedTimeline = PresentedTimeline(
            selectedDay: selectedDay,
            sourceDay: sourceDay
        )
    }

    private func timelineDayDidChange(
        _ selectedDay: TimelineDayKey
    ) -> TimelineDayKey {
        if let nearest = model.nearestDay(to: selectedDay) {
            return nearest
        }
        emptyTransitionDay = selectedDay
        return selectedDay
    }

    private func timelineDidDismiss() {
        model.reload(in: modelContext)
    }
}

private struct HomeFeedContent: View {
    let model: HomeFeedModel
    let namespace: Namespace.ID
    let emptyTransitionDay: TimelineDayKey
    let scrollRequest: HomeFeedScrollRequest?
    let onVisibleDayChange: (TimelineDayKey) -> Void
    let onOpenDay: (TimelineDayKey) -> Void
    let onStartToday: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 32) {
                    if let errorMessage = model.errorMessage {
                        HomeFeedErrorView(message: errorMessage)
                    } else if model.rows.isEmpty {
                        HomeFeedEmptyView(onStartToday: onStartToday)
                            .matchedTransitionSource(
                                id: emptyTransitionDay,
                                in: namespace
                            )
                    } else {
                        ForEach(model.rows) { rowModel in
                            HomeFeedDayRow(
                                model: rowModel,
                                namespace: namespace,
                                onOpen: { onOpenDay(rowModel.id) }
                            )
                            .id(rowModel.id)
                        }
                    }
                }
                .scrollTargetLayout()
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .contentMargins(.bottom, 100, for: .scrollContent)
            .onScrollTargetVisibilityChange(
                idType: TimelineDayKey.self,
                threshold: 0.1
            ) { visibleDays in
                if let first = visibleDays.first {
                    onVisibleDayChange(first)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollContentBackground(.hidden)
            .task {
                guard let lastDay = model.rows.last?.id else { return }
                proxy.scrollTo(lastDay, anchor: .bottom)
            }
            .task(id: scrollRequest?.id) {
                guard let scrollRequest else { return }
                withAnimation(.smooth) {
                    proxy.scrollTo(scrollRequest.day)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct HomeFeedDayRow: View {
    let model: DaySummaryRowModel
    let namespace: Namespace.ID
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    DaySummaryDatePresentation.dayTitle(
                        for: model.summary.day
                    )
                )
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

                DaySummaryCardContent(model: model)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: model.id, in: namespace)
        .accessibilityHint("Opens this day’s timeline")
        .task {
            await model.loadEnrichment()
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
    @State private var sourceDay: TimelineDayKey
    let namespace: Namespace.ID
    let onDayChange: (TimelineDayKey) -> TimelineDayKey

    init(
        initialDay: TimelineDayKey,
        initialSourceDay: TimelineDayKey,
        namespace: Namespace.ID,
        onDayChange: @escaping (TimelineDayKey) -> TimelineDayKey
    ) {
        _selectedDay = State(initialValue: initialDay)
        _sourceDay = State(initialValue: initialSourceDay)
        self.namespace = namespace
        self.onDayChange = onDayChange
    }

    var body: some View {
        NavigationStack {
            DayTimelineScreen(selectedDay: $selectedDay)
        }
        .navigationTransition(.zoom(sourceID: sourceDay, in: namespace))
        .onChange(of: selectedDay) { _, selectedDay in
            sourceDay = onDayChange(selectedDay)
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
