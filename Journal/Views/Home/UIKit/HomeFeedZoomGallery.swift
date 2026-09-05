#if DEBUG
import SwiftData
import SwiftUI

/// Deterministic, non-persisted content for checking the actual UIKit feed on a
/// device: launch with -home-zoom-gallery. No journal records are inserted.
struct HomeFeedZoomGallery: View {
    @Environment(\.modelContext) private var modelContext
    @State private var scale: JournalSummaryScale = .days
    @State private var request: HomeFeedScrollRequest?
    private let days = DaySummaryGalleryFixtures.rows

    var body: some View {
        NavigationStack {
            Feed(context: modelContext, scale: scale, request: request, days: days)
                .ignoresSafeArea(.container, edges: [.top, .bottom])
                .navigationTitle("Zoom Gallery")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        Picker("Summary scale", selection: $scale) {
                            ForEach(JournalSummaryScale.allCases) { scale in
                                Text(scale.title).tag(scale)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }
                }
                .onChange(of: scale) { _, value in
                    request = HomeFeedScrollRequest(scale: value, anchor: anchor(for: value), alignment: .top, preservesZoomViewport: true)
                }
        }
    }

    private func anchor(for scale: JournalSummaryScale) -> HomeFeedAnchor {
        switch scale {
        case .days: .day(days[0].id)
        case .months: .period(.month(MonthKey(year: 2026, month: 7)))
        case .years: .period(.year(YearKey(year: 2026)))
        }
    }

    private struct Feed: UIViewControllerRepresentable {
        let context: ModelContext
        let scale: JournalSummaryScale
        let request: HomeFeedScrollRequest?
        let days: [DaySummaryRowModel]

        func makeUIViewController(context: Context) -> HomeFeedViewController { HomeFeedViewController() }

        func updateUIViewController(_ controller: HomeFeedViewController, context: Context) {
            controller.update(modelContext: self.context, dayRows: days,
                monthRows: HomeFeedZoomGalleryFixtures.months,
                yearRows: HomeFeedZoomGalleryFixtures.years, errorMessage: nil,
                scale: scale, contentRevision: 0, emptyTransitionDay: days[0].id,
                scrollRequest: request,
                callbacks: .init(onVisibleAnchorChange: { _, _ in }, onScrollRequestApplied: { _ in },
                    onUserScroll: {}, onOpenDay: { _ in }, onOpenPeriod: { _ in },
                    onOpenPeriodDay: { _, _ in }, onStartToday: {},
                    onTimelineDayChange: { .day($0) }, onTimelineDismiss: {}))
        }

    }
}

enum HomeFeedZoomGalleryFixtures {
    static let days = DaySummaryGalleryFixtures.rows
    static let months = [period(.month(MonthKey(year: 2026, month: 7)))]
    static let years = [period(.year(YearKey(year: 2026)))]

    private static func period(_ key: PeriodSummaryKey) -> PeriodSummaryRowModel {
        let sample = PeriodSummary.galleryPreview
        let isYear: Bool = if case .year = key { true } else { false }
        return PeriodSummaryRowModel(summary: PeriodSummary(
            key: key, days: days.map(\.summary), entryCount: sample.entryCount,
            overviewData: sample.overviewData, people: sample.people,
            movement: sample.movement, frequentRoute: sample.frequentRoute,
            mostVisitedPlace: sample.mostVisitedPlace, cities: sample.cities,
            countries: isYear ? sample.countries : [],
            photos: days.flatMap { $0.summary.photos }, totalPhotoCount: 42,
            busiestDay: days[0].id, busiestMonth: MonthKey(year: 2026, month: 7),
            longestJourney: sample.longestJourney, sleep: sample.sleep,
            activity: isYear ? Array(sample.activity.prefix(12)) : sample.activity,
            reviewCount: sample.reviewCount, newGroundCount: isYear ? 6 : 0))
    }
}
#endif
