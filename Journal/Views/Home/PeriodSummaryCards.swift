import MapKit
import SwiftUI

struct PeriodSummaryCardContent: View {
    let model: PeriodSummaryRowModel
    let loadsDeferredContent: Bool
    let onOpenDay: (TimelineDayKey) -> Void

    init(
        model: PeriodSummaryRowModel,
        loadsDeferredContent: Bool = true,
        onOpenDay: @escaping (TimelineDayKey) -> Void
    ) {
        self.model = model
        self.loadsDeferredContent = loadsDeferredContent
        self.onOpenDay = onOpenDay
    }

    var body: some View {
        let recipe = model.layoutRecipe
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(recipe.placements) { placement in
                    PeriodSummaryTile(
                        model: model,
                        tile: placement.tile,
                        loadsDeferredContent: loadsDeferredContent,
                        onOpenDay: onOpenDay
                    )
                    .frame(
                        width: placement.frame.width * proxy.size.width,
                        height: placement.frame.height * proxy.size.width
                    )
                    .offset(
                        x: placement.frame.x * proxy.size.width,
                        y: placement.frame.y * proxy.size.width
                    )
                }
            }
        }
        .aspectRatio(
            PeriodSummaryLayoutRecipe.referenceWidth / recipe.referenceHeight,
            contentMode: .fit
        )
    }
}

private struct PeriodSummaryTile: View {
    let model: PeriodSummaryRowModel
    let tile: PeriodSummaryTileKind
    let loadsDeferredContent: Bool
    let onOpenDay: (TimelineDayKey) -> Void

    private var summary: PeriodSummary { model.summary }

    @ViewBuilder var body: some View {
        switch tile {
            case .overview:
                DaySummaryOverviewMap(
                    cacheSlotID: "period-\(summary.id.id)-overview",
                    data: model.overviewData,
                    loadsContent: loadsDeferredContent
                )
                    .accessibilityLabel("Map of this period")
            case .people:
                PeriodPeopleTile(people: summary.people)
            case .movement:
                if let movement = summary.movement {
                    PeriodMovementTile(movement: movement)
                }
            case .frequentRoute:
                if let route = summary.frequentRoute {
                    PeriodRouteTile(
                        cacheSlotID: "period-\(summary.id.id)-frequent-route",
                        route: route,
                        mapData: model.frequentRouteData ?? route.mapData,
                        loadsContent: loadsDeferredContent
                    )
                }
            case .place:
                if let place = summary.mostVisitedPlace {
                    PeriodPlaceTile(
                        place: place
                    )
                }
            case .cities:
                PeriodGeographyTile(
                    values: summary.cities,
                    kind: .cities
                )
            case .countries:
                PeriodGeographyTile(
                    values: summary.countries,
                    kind: .countries
                )
            case .photos:
                PeriodPhotosTile(
                    references: summary.photos,
                    totalCount: summary.totalPhotoCount,
                    loadsContent: loadsDeferredContent
                )
            case .busiestDay:
                if let day = summary.busiestDay {
                    PeriodHighlightButton(
                        eyebrow: "Busiest Day",
                        title: DaySummaryDatePresentation.dayTitle(for: day),
                        symbol: "flame.fill",
                        tint: .orange,
                        action: { onOpenDay(day) }
                    )
                }
            case .longestJourney:
                if let journey = summary.longestJourney {
                    PeriodJourneyTile(
                        cacheSlotID: "period-\(summary.id.id)-longest-journey",
                        journey: journey,
                        mapData: model.longestJourneyData ?? journey.mapData,
                        loadsContent: loadsDeferredContent
                    ) {
                        onOpenDay(journey.day)
                    }
                }
            case .review:
                PeriodReviewTile(count: summary.reviewCount)
            case .sleep:
                if let sleep = summary.sleep {
                    PeriodSleepTile(sleep: sleep)
                }
            case .activity:
                PeriodActivityTile(summary: summary)
            case .newGround:
                PeriodNewGroundTile(count: summary.newGroundCount)
        }
    }
}

private struct PeriodTileBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: .rect(cornerRadius: 16)
            )
            .clipShape(.rect(cornerRadius: 16))
    }
}

private extension View {
    func periodTileBackground() -> some View {
        modifier(PeriodTileBackground())
    }
}

private struct PeriodPeopleTile: View {
    let people: [PeriodPersonSummary]

    var body: some View {
        GeometryReader { proxy in
            let visible = Array(people.prefix(18))
            let placements = EntryDetailPeopleConstellationMetrics.placements(
                count: visible.count
            )
            let isCompact = proxy.size.height < 90
            let labelHeight: CGFloat = isCompact ? 18 : 20
            let verticalPadding: CGFloat = isCompact ? 3 : 6
            let contentHeight = max(
                0,
                proxy.size.height - labelHeight - verticalPadding * 2
            )
            let scale = min(
                EntryDetailPeopleConstellationMetrics.scale(
                    for: proxy.size.width - 12,
                    placements: placements
                ),
                contentHeight / EntryDetailPeopleConstellationMetrics.height
            )
            ZStack(alignment: .bottom) {
                ForEach(visible.enumerated(), id: \.element.id) { index, item in
                    let placement = placements[index]
                    PersonAvatar(
                        name: item.person.name,
                        contactIdentifier: item.person.contactIdentifier,
                        size: placement.diameter * scale
                    )
                    .position(
                        x: proxy.size.width / 2 + placement.center.x * scale,
                        y: verticalPadding + contentHeight / 2
                            + placement.center.y * scale
                    )
                }
                Text("\(people.count) people")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 5)
            }
        }
        .periodTileBackground()
        .accessibilityLabel("\(people.count) people")
    }
}

private struct PeriodMovementTile: View {
    let movement: DayMovementSummary

    var body: some View {
        GeometryReader { proxy in
            let badgeSize = min(36, max(28, proxy.size.height * 0.42))
            ZStack(alignment: .topLeading) {
                HStack(spacing: -badgeSize / 2) {
                    ForEach(movement.icons.prefix(5)) { icon in
                        DaySummaryMovementBadge(icon: icon, size: badgeSize)
                    }
                }
                .padding(.trailing, badgeSize / 2)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                metricsLabel
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .bottomLeading
                )
            }
            .padding(8)
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .topLeading
            )
        }
        .periodTileBackground()
    }

    private var metricsLabel: some View {
        Text(metrics)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .allowsTightening(true)
            .minimumScaleFactor(0.75)
    }

    private var metrics: String {
        let distance = movement.distanceMeters.map {
            ($0 / 1_000).formatted(.number.precision(.fractionLength(0...1))) + " km"
        }
        let duration = movement.durationSeconds.map {
            Duration.seconds($0).formatted(.units(
                allowed: [.days, .hours, .minutes],
                width: .narrow,
                maximumUnitCount: 2
            ))
        }
        return [distance, duration].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct PeriodRouteTile: View {
    let cacheSlotID: String
    let route: PeriodRouteSummary
    let mapData: TimelineOverviewData
    let loadsContent: Bool

    var body: some View {
        GeometryReader { proxy in
            DaySummaryOverviewMap(
                cacheSlotID: cacheSlotID,
                data: mapData,
                loadsContent: loadsContent
            )
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottomLeading) {
                    VariableBlurView(
                        maxBlurRadius: 7,
                        direction: .blurredBottomClearTop,
                        startOffset: 0.3
                    )
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.26)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    if proxy.size.width < 130 {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(route.count)× route")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.84))
                            Text(route.originName)
                            Text("↓ \(route.destinationName)")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(7)
                    } else {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Favorite route · \(route.count) times")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.82))
                            Text("\(route.originName) ↔ \(route.destinationName)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .padding(8)
                    }
                }
                .frame(height: proxy.size.width < 130 ? 66 : 50)
                .clipped()
                .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: 16))
        }
        .accessibilityLabel(
            "Most frequent route, \(route.count) times from \(route.originName) to \(route.destinationName)"
        )
    }
}

private struct PeriodPlaceTile: View {
    let place: PeriodPlaceSummary

    var body: some View {
        TimelinePlaceMiniMap(
            location: place.location,
            needsReview: false
        )
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottomLeading) {
                    VariableBlurView(
                        maxBlurRadius: 4,
                        direction: .blurredBottomClearTop,
                        startOffset: 0.42
                    )
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.22)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    Text("\(place.visitCount) visits")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(7)
                }
                .frame(height: 34)
                .clipped()
                .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: 16))
    }
}

private enum PeriodGeographyKind: Equatable {
    case cities
    case countries
}

private struct PeriodGeographyTile: View {
    let values: [PeriodGeographySummary]
    let kind: PeriodGeographyKind

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: -3) {
                ForEach(values.prefix(3)) { value in
                    Text(kind == .countries
                         ? flag(for: value.code)
                         : cityMonogram(value.name))
                        .font(kind == .countries
                              ? .caption : .system(size: 8, weight: .bold))
                        .foregroundStyle(
                            kind == .countries ? Color.primary : Color.white
                        )
                        .frame(width: 25, height: 25)
                        .background(
                            cityBubble(for: value),
                            in: .circle
                        )
                }
            }
            switch kind {
            case .cities:
                Text(values.count == 1 ? "1 city" : "\(values.count) cities")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            case .countries:
                Text(values.count == 1 ? "1 country" : "\(values.count) countries")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .periodTileBackground()
    }

    private func cityMonogram(_ name: String) -> String {
        String(name.prefix(3)).uppercased()
    }

    private func cityBubble(for value: PeriodGeographySummary) -> LinearGradient {
        let seed = stableSeed(for: value.name)
        let hue = Double(seed % 360) / 360
        let saturation = 0.42 + Double((seed >> 9) % 12) / 100
        let brightness = 0.72 + Double((seed >> 17) % 10) / 100
        return LinearGradient(
            colors: [
                Color(
                    hue: hue,
                    saturation: max(0.2, saturation - 0.08),
                    brightness: min(0.92, brightness + 0.12)
                ),
                Color(
                    hue: hue,
                    saturation: min(0.68, saturation + 0.08),
                    brightness: max(0.48, brightness - 0.14)
                ),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func stableSeed(for value: String) -> UInt64 {
        value.uppercased().unicodeScalars.reduce(1_469_598_103_934_665_603) {
            ($0 ^ UInt64($1.value)) &* 1_099_511_628_211
        }
    }

    private func flag(for code: String?) -> String {
        guard let code, code.count == 2 else { return "🌐" }
        return code.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127_397 + $0.value).map(String.init)
        }.joined()
    }
}

private struct PeriodPhotosTile: View {
    let references: [PhotoReference]
    let totalCount: Int
    let loadsContent: Bool

    var body: some View {
        GeometryReader { proxy in
            let visible = Array(references.prefix(4))
            let gap = 6.0
            let metrics = PeriodPhotoGridMetrics.best(
                itemCount: visible.count,
                size: proxy.size,
                gap: gap
            )
            let contentWidth = metrics.side * CGFloat(metrics.columns)
                + gap * CGFloat(max(0, metrics.columns - 1))
            let contentHeight = metrics.side * CGFloat(metrics.rows)
                + gap * CGFloat(max(0, metrics.rows - 1))
            let origin = CGPoint(
                x: (proxy.size.width - contentWidth) / 2,
                y: (proxy.size.height - contentHeight) / 2
            )
            ZStack(alignment: .topLeading) {
                ForEach(visible.enumerated(), id: \.element.id) { index, reference in
                    DaySummaryPhotoThumbnail(
                        reference: reference,
                        previewIndex: index,
                        loadsContent: loadsContent
                    )
                    .frame(width: metrics.side, height: metrics.side)
                    .clipShape(.rect(cornerRadius: visible.count == 1 ? 18 : 14))
                    .offset(
                        x: origin.x
                            + CGFloat(index % metrics.columns)
                            * (metrics.side + gap),
                        y: origin.y
                            + CGFloat(index / metrics.columns)
                            * (metrics.side + gap)
                    )
                }
            }
        }
        .accessibilityLabel("\(totalCount) photos")
    }
}

private struct PeriodPhotoGridMetrics {
    let columns: Int
    let rows: Int
    let side: CGFloat

    static func best(
        itemCount: Int,
        size: CGSize,
        gap: CGFloat
    ) -> Self {
        guard itemCount > 0 else {
            return Self(columns: 1, rows: 1, side: 0)
        }
        return (1...itemCount).map { columns in
            let rows = Int(ceil(Double(itemCount) / Double(columns)))
            let width = (size.width - gap * CGFloat(columns - 1))
                / CGFloat(columns)
            let height = (size.height - gap * CGFloat(rows - 1))
                / CGFloat(rows)
            return Self(
                columns: columns,
                rows: rows,
                side: max(0, min(width, height))
            )
        }.max {
            if abs($0.side - $1.side) > 3 {
                return $0.side < $1.side
            }
            let lhsEmpty = $0.columns * $0.rows - itemCount
            let rhsEmpty = $1.columns * $1.rows - itemCount
            if lhsEmpty != rhsEmpty { return lhsEmpty > rhsEmpty }
            let lhsImbalance = abs($0.columns - $0.rows)
            let rhsImbalance = abs($1.columns - $1.rows)
            if lhsImbalance != rhsImbalance {
                return lhsImbalance > rhsImbalance
            }
            return $0.columns > $1.columns
        }!
    }
}

private struct PeriodHighlightButton: View {
    let eyebrow: LocalizedStringKey
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 76
            ZStack(alignment: .topLeading) {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                        .foregroundStyle(tint)
                    Text(eyebrow)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.72)
                }
                .font(
                    isCompact
                        ? .caption2.weight(.semibold)
                        : .caption.weight(.semibold)
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                Text(title)
                    .font(
                        isCompact
                            ? .caption.weight(.semibold)
                            : .subheadline.weight(.semibold)
                    )
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .bottomLeading
                    )
            }
            .padding(isCompact ? 7 : 9)
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .topLeading
            )
        }
        .periodTileBackground()
        .contentShape(.rect)
        .highPriorityGesture(TapGesture().onEnded(action))
    }
}

private struct PeriodJourneyTile: View {
    let cacheSlotID: String
    let journey: PeriodJourneySummary
    let mapData: TimelineOverviewData
    let loadsContent: Bool
    let action: () -> Void

    var body: some View {
        GeometryReader { proxy in
            DaySummaryOverviewMap(
                cacheSlotID: cacheSlotID,
                data: mapData,
                loadsContent: loadsContent
            )
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottomLeading) {
                    VariableBlurView(
                        maxBlurRadius: 7,
                        direction: .blurredBottomClearTop,
                        startOffset: 0.3
                    )
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.28)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    if proxy.size.width < 130 {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(distance)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.86))
                            Text(journey.originName)
                            Text("↓ \(journey.destinationName)")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(7)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Longest journey · \(distance)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.86))
                            Text("\(journey.originName) → \(journey.destinationName)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .padding(8)
                    }
                }
                .frame(height: proxy.size.width < 130 ? 66 : 50)
                .clipped()
                .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: 16))
        }
        .contentShape(.rect)
        .highPriorityGesture(TapGesture().onEnded(action))
    }

    private var distance: String {
        (journey.distanceMeters / 1_000).formatted(
            .number.precision(.fractionLength(0...1))
        ) + " km"
    }
}

private struct PeriodReviewTile: View {
    let count: Int

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.height > proxy.size.width * 0.92 {
                VStack(alignment: .leading, spacing: 8) {
                    ReviewBadge(size: 25)
                    reviewLabel
                }
                .padding(8)
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .leading
                )
            } else {
                HStack(spacing: 6) {
                    ReviewBadge(size: 19)
                    reviewLabel
                }
                .padding(7)
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .leading
                )
            }
        }
        .periodTileBackground()
    }

    private var reviewLabel: some View {
        Text("\(count) Needs Review")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
    }
}

private struct PeriodNewGroundTile: View {
    let count: Int

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 76
            ZStack(alignment: .topLeading) {
                Image(systemName: "sparkles")
                    .font(isCompact ? .caption.weight(.semibold) : .title3)
                    .foregroundStyle(.mint)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                label
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .bottomLeading
                    )
            }
            .padding(isCompact ? 7 : 8)
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .topLeading
            )
        }
        .periodTileBackground()
    }

    private var label: some View {
        Text("\(count) new places")
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
            .minimumScaleFactor(0.75)
    }
}

private struct PeriodSleepTile: View {
    let sleep: PeriodSleepSummary

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 76
            ZStack(alignment: .topLeading) {
                Image(systemName: "sunrise.fill")
                    .font(isCompact ? .caption.weight(.semibold) : .title3)
                    .foregroundStyle(.cyan)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                wakeLabels
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .bottomLeading
                    )
            }
            .padding(isCompact ? 7 : 8)
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .topLeading
            )
        }
        .periodTileBackground()
    }

    private var wakeLabels: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(wakeTime)
                .font(.subheadline.weight(.bold))
            Text("±\(sleep.consistencyMinutes)m rhythm")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
    }

    private var wakeTime: String {
        let hours = sleep.averageWakeMinute / 60
        let minutes = sleep.averageWakeMinute % 60
        return String(format: "%d:%02d", hours, minutes)
    }
}

private struct PeriodActivityTile: View {
    let summary: PeriodSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(
                    summary.monthKey == nil ? "Year Rhythm" : "Day Rhythm",
                    systemImage: "square.grid.3x3.fill"
                )
                .font(.caption2.weight(.semibold))
            }
            GeometryReader { proxy in
                let values = summary.activity
                let gap = 3.0
                let width = max(2, (proxy.size.width
                    - gap * CGFloat(max(0, values.count - 1)))
                    / CGFloat(max(1, values.count)))
                let peak = max(values.max() ?? 1, 1)
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(values.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: min(3, width / 2))
                            .fill(Color.accentColor.opacity(
                                values[index] == 0
                                    ? 0.12
                                    : 0.3 + 0.7 * Double(values[index]) / Double(peak)
                            ))
                            .frame(
                                width: width,
                                height: max(
                                    4,
                                    proxy.size.height
                                        * CGFloat(values[index]) / CGFloat(peak)
                                )
                            )
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .periodTileBackground()
    }
}

#if DEBUG
struct PeriodSummaryDesignGallery: View {
    private let row = PeriodSummaryRowModel(summary: .galleryPreview)
    @State private var scale: JournalSummaryScale = .months
    @Namespace private var timelineTransition

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("July 2026")
                        .font(.title2.weight(.bold))
                    PeriodSummaryCardContent(
                        model: row,
                        onOpenDay: { _ in }
                    )
                }
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("2026")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                HomeBottomToolbar(
                    scale: $scale,
                    namespace: timelineTransition,
                    onToday: {},
                    onScaleReselected: { _ in },
                    onSearch: {}
                )
            }
        }
    }
}

extension PeriodSummary {
    static var galleryPreview: PeriodSummary {
        let day = TimelineDayKey(year: 2026, month: 7, day: 26)
        let identifier = TimelineOccurrenceID(
            entryID: UUID(),
            day: day,
            timeZoneIdentifier: "Europe/Bucharest",
            role: .intervalDay
        )
        let home = TimelineLocationSnapshot(
            name: "Home",
            latitude: 44.18,
            longitude: 28.61,
            systemImage: .house,
            cityName: "Constanța",
            countryName: "Romania",
            countryCode: "RO"
        )
        let beach = TimelineLocationSnapshot(
            name: "Reyna Beach",
            latitude: 44.25,
            longitude: 28.63,
            systemImage: .beach,
            cityName: "Constanța",
            countryName: "Romania",
            countryCode: "RO"
        )
        let map = TimelineOverviewData(
            markers: [
                TimelineMapMarker(location: home),
                TimelineMapMarker(location: beach),
            ],
            paths: [
                TimelineMapPath(
                    id: UUID(),
                    kind: .transit("Car"),
                    coordinates: TimelineOverviewData.curvedCoordinates(
                        from: home.coordinate,
                        to: beach.coordinate,
                        bendPositive: true
                    )
                ),
            ]
        )
        let people = [
            "Emma", "Daria", "Robert", "Ana", "Victor", "Teo",
            "Radu", "Mara", "Sofia", "Paul", "Alex", "Nora",
            "Iris", "Dan", "Ioana", "Vlad", "Maria", "Tudor",
        ].map {
            PeriodPersonSummary(
                person: TimelinePersonSnapshot(
                    id: UUID(),
                    name: $0,
                    contactIdentifier: nil
                ),
                loggedDuration: 10_000,
                dayCount: 4,
                entryCount: 5
            )
        }
        let movement = DayMovementSummary(
            icons: [
                DayMovementIcon(id: identifier, kind: .transit("Bolt")),
                DayMovementIcon(id: identifier, kind: .transit("Car")),
                DayMovementIcon(id: identifier, kind: .transit("Train")),
                DayMovementIcon(id: identifier, kind: .workout("figure.walk")),
            ],
            distanceMeters: 1_284_000,
            durationSeconds: 96_000,
            needsReview: false
        )
        return PeriodSummary(
            key: .month(MonthKey(year: 2026, month: 7)),
            days: [],
            entryCount: 87,
            overviewData: map,
            people: people,
            movement: movement,
            frequentRoute: PeriodRouteSummary(
                count: 10,
                originName: "Home",
                destinationName: "Reyna Beach",
                mapData: map
            ),
            mostVisitedPlace: PeriodPlaceSummary(
                location: beach,
                duration: 80_000,
                visitCount: 9
            ),
            cities: [
                .init(name: "Constanța", code: nil, visitCount: 18),
                .init(name: "Brașov", code: nil, visitCount: 5),
                .init(name: "Bucharest", code: nil, visitCount: 3),
            ],
            countries: [
                .init(name: "Romania", code: "RO", visitCount: 20),
                .init(name: "Bulgaria", code: "BG", visitCount: 2),
            ],
            photos: (0..<4).map {
                PhotoReference(assetLocalIdentifier: "gallery-\($0)")
            },
            totalPhotoCount: 42,
            busiestDay: day,
            busiestMonth: nil,
            longestJourney: PeriodJourneySummary(
                day: day,
                distanceMeters: 295_000,
                originName: "Constanța",
                destinationName: "Bucharest",
                mapData: map
            ),
            sleep: PeriodSleepSummary(
                sampleCount: 20,
                averageWakeMinute: 8 * 60 + 18,
                averageDuration: 30_600,
                consistencyMinutes: 24
            ),
            activity: [1, 0, 2, 4, 1, 3, 7, 0, 2, 2, 5, 1, 4, 6, 3, 0, 1, 5, 3, 2, 4, 7, 6, 2, 1, 3, 5, 4, 2, 6, 3],
            reviewCount: 3,
            newGroundCount: 6
        )
    }
}
#endif
