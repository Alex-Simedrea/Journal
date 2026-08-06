import SwiftUI

struct DaySummaryCardContent: View {
    let model: DaySummaryRowModel
    let loadsDeferredContent: Bool

    init(
        model: DaySummaryRowModel,
        loadsDeferredContent: Bool = true
    ) {
        self.model = model
        self.loadsDeferredContent = loadsDeferredContent
    }

    var body: some View {
        let recipe = DaySummaryLayoutRecipe.make(for: model.summary)

        GeometryReader { proxy in
            DaySummaryTileCanvas(
                model: model,
                recipe: recipe,
                size: proxy.size,
                loadsDeferredContent: loadsDeferredContent
            )
        }
        .aspectRatio(
            DaySummaryLayoutRecipe.referenceWidth / recipe.referenceHeight,
            contentMode: .fit
        )
    }
}

private struct DaySummaryTileCanvas: View {
    let model: DaySummaryRowModel
    let recipe: DaySummaryLayoutRecipe
    let size: CGSize
    let loadsDeferredContent: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(recipe.placements) { placement in
                DaySummaryTile(
                    model: model,
                    tile: placement.tile,
                    loadsDeferredContent: loadsDeferredContent
                )
                    .frame(
                        width: placement.frame.width * size.width,
                        height: placement.frame.height * size.width
                    )
                    .offset(
                        x: placement.frame.x * size.width,
                        y: placement.frame.y * size.width
                    )
            }
        }
    }
}

private struct DaySummaryTile: View {
    let model: DaySummaryRowModel
    let tile: DaySummaryTileKind
    let loadsDeferredContent: Bool

    var body: some View {
        ZStack {
            switch tile {
            case .overview:
                DaySummaryOverviewMap(
                    cacheSlotID: "day-\(model.id.id)-overview",
                    data: model.overviewData,
                    loadsContent: loadsDeferredContent
                )
            case .weather:
                DaySummaryWeatherTile(
                    state: model.weatherState,
                    request: model.summary.weatherRequest
                )
            case .people:
                DaySummaryPeopleTile(
                    people: model.summary.people,
                    needsReview: model.summary.peopleNeedReview
                )
            case .photos:
                DaySummaryPhotoTile(
                    references: model.summary.photos,
                    loadsContent: loadsDeferredContent
                )
            case .movement:
                if let movement = model.summary.movement {
                    DaySummaryMovementTile(movement: movement)
                }
            case .wakeUp:
                if let wakeUp = model.summary.wakeUp {
                    DaySummaryWakeUpTile(wakeUp: wakeUp)
                }
            case .featuredPlace:
                if let featuredPlace = model.summary.featuredPlace {
                    DaySummaryPlaceMap(
                        featuredPlace: featuredPlace
                    )
                }
            case .review:
                DaySummaryNeedsReviewTile()
            }
        }
    }
}

private struct DaySummaryWeatherTile: View {
    let state: DayWeatherLoadState
    let request: DayWeatherRequest?

    var body: some View {
        GeometryReader { proxy in
            TimelineWeatherTile(
                weather: weather,
                layout: proxy.size.height < 60 ? .compact : .large,
                location: location,
                timeZoneIdentifier: request?.timeZoneIdentifier
                    ?? TimeZone.current.identifier,
                isLoading: state == .idle || state == .loading,
                presentationDate: request?.presentationDate
            )
        }
    }

    private var weather: EntryWeather? {
        guard case .loaded(let weather) = state else { return nil }
        return EntryWeather(
            condition: weather.condition,
            symbolName: weather.symbolName,
            temperatureCelsius: weather.highTemperatureCelsius,
            humidity: weather.maximumHumidity,
            date: request?.presentationDate ?? weather.date
        )
    }

    private var location: TimelineLocationSnapshot? {
        guard let request else { return nil }
        return TimelineLocationSnapshot(
            name: "Weather",
            latitude: request.latitude,
            longitude: request.longitude
        )
    }
}

private struct DaySummaryPeopleTile: View {
    let people: [TimelinePersonSnapshot]
    let needsReview: Bool

    var body: some View {
        GeometryReader { proxy in
            let visiblePeople = Array(people.prefix(12))
            let verticalPadding = 4.0
            let contentHeight = max(
                0,
                proxy.size.height - verticalPadding * 2
            )
            let placements = EntryDetailPeopleConstellationMetrics.placements(
                count: visiblePeople.count
            )
            let widthScale = EntryDetailPeopleConstellationMetrics.scale(
                for: proxy.size.width,
                placements: placements
            )
            let heightScale = contentHeight
                / EntryDetailPeopleConstellationMetrics.height
            let scale = min(widthScale, heightScale)

            ZStack {
                Color(uiColor: .secondarySystemGroupedBackground)
                ForEach(visiblePeople.enumerated(), id: \.element.id) {
                    index, person in
                    let placement = placements[index]
                    PersonAvatar(
                        name: person.name,
                        contactIdentifier: person.contactIdentifier,
                        size: placement.diameter * scale
                    )
                    .position(
                        x: proxy.size.width / 2
                            + placement.center.x * scale,
                        y: verticalPadding + contentHeight / 2
                            + placement.center.y * scale
                    )
                }
            }
        }
        .clipShape(.rect(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            if needsReview {
                ReviewBadge(size: 15).padding(4)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct DaySummaryPhotoTile: View {
    let references: [PhotoReference]
    let loadsContent: Bool

    var body: some View {
        GeometryReader { proxy in
            let visible = references.prefix(4)
            let gap = 6.0
            let columns = references.count == 1 ? 1 : 2
            let rows = references.count >= 3 ? 2 : 1
            let width = (
                proxy.size.width - gap * CGFloat(columns - 1)
            ) / CGFloat(columns)
            let height = (
                proxy.size.height - gap * CGFloat(rows - 1)
            ) / CGFloat(rows)

            ZStack(alignment: .topLeading) {
                ForEach(visible.enumerated(), id: \.element.id) {
                    index, reference in
                    DaySummaryPhotoThumbnail(
                        reference: reference,
                        previewIndex: index,
                        loadsContent: loadsContent
                    )
                        .overlay {
                            if index == 3, references.count > 4 {
                                ZStack {
                                    Color.black.opacity(0.48)
                                    Text("+\(references.count - 4)")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .frame(width: width, height: height)
                        .clipShape(
                            .rect(cornerRadius: references.count == 1 ? 16 : 10)
                        )
                        .offset(
                            x: CGFloat(index % columns) * (width + gap),
                            y: CGFloat(index / columns) * (height + gap)
                        )
                }
            }
        }
    }
}

struct DaySummaryPhotoThumbnail: View {
    let reference: PhotoReference
    let previewIndex: Int
    let loadsContent: Bool

    init(
        reference: PhotoReference,
        previewIndex: Int,
        loadsContent: Bool = true
    ) {
        self.reference = reference
        self.previewIndex = previewIndex
        self.loadsContent = loadsContent
    }

    @ViewBuilder var body: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-day-summary-gallery") {
            LinearGradient(
                colors: previewColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: previewIndex.isMultiple(of: 2)
                    ? "water.waves"
                    : "tree.fill")
                    .foregroundStyle(.white.opacity(0.8))
            }
        } else {
            TimelinePhotoThumbnail(
                reference: reference,
                loadsContent: loadsContent,
                usesSummaryCache: true
            )
        }
#else
        TimelinePhotoThumbnail(
            reference: reference,
            loadsContent: loadsContent,
            usesSummaryCache: true
        )
#endif
    }

    private var previewColors: [Color] {
        switch previewIndex % 4 {
        case 0: [Color(hex: 0x4A86A8), Color(hex: 0xD7B482)]
        case 1: [Color(hex: 0x7B634A), Color(hex: 0xD6D0B9)]
        case 2: [Color(hex: 0x4E738C), Color(hex: 0xA6C397)]
        default: [Color(hex: 0x567C65), Color(hex: 0xCFC39E)]
        }
    }
}

private struct DaySummaryMovementTile: View {
    let movement: DayMovementSummary

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height
                < DaySummaryLayoutRecipe.movementExpansionThreshold
            let horizontalPadding = 8.0
            let availableBadgeWidth = max(
                0,
                proxy.size.width - horizontalPadding * 2
            )
            if isCompact {
                HStack(spacing: 0) {
                    DaySummaryMovementBadges(
                        icons: movement.icons.prefix(2),
                        size: fittingBadgeSize(
                            maximum: 27,
                            iconCount: min(movement.icons.count, 2),
                            availableWidth: availableBadgeWidth
                        )
                    )
                    if let distanceText {
                        Text(distanceText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    DaySummaryMovementBadges(
                        icons: movement.icons.prefix(5),
                        size: fittingBadgeSize(
                            maximum: 30,
                            iconCount: min(movement.icons.count, 5),
                            availableWidth: availableBadgeWidth
                        )
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 4)
                    if let metricsText {
                        Text(metricsText)
                            .font(.subheadline.weight(.regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: .rect(cornerRadius: 16)
        )
        .overlay(alignment: .topTrailing) {
            if movement.needsReview {
                ReviewBadge(size: 15).padding(4)
            }
        }
    }

    private func fittingBadgeSize(
        maximum: CGFloat,
        iconCount: Int,
        availableWidth: CGFloat
    ) -> CGFloat {
        guard iconCount > 0 else { return maximum }
        let fittingSize = availableWidth * 2 / CGFloat(iconCount + 1)
        return min(maximum, fittingSize)
    }

    private var distanceText: String? {
        guard let meters = movement.distanceMeters else { return nil }
        let kilometers = meters / 1_000
        let precision: FloatingPointFormatStyle<Double>.Configuration.Precision =
            kilometers < 10 ? .fractionLength(0...1) : .fractionLength(0)
        return kilometers.formatted(.number.precision(precision)) + "km"
    }

    private var durationText: String? {
        guard let seconds = movement.durationSeconds else { return nil }
        let totalMinutes = Int(seconds.rounded()) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h\(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    private var metricsText: String? {
        switch (distanceText, durationText) {
        case let (distance?, duration?): "\(distance) · \(duration)"
        case let (distance?, nil): distance
        case let (nil, duration?): duration
        case (nil, nil): nil
        }
    }
}

private struct DaySummaryMovementBadges: View {
    let icons: ArraySlice<DayMovementIcon>
    let size: CGFloat

    var body: some View {
        HStack(spacing: -size / 2) {
            ForEach(icons) { icon in
                DaySummaryMovementBadge(icon: icon, size: size)
            }
        }
    }
}

struct DaySummaryMovementBadge: View {
    let icon: DayMovementIcon
    let size: CGFloat

    var body: some View {
        ZStack {
            switch icon.kind {
            case .transit(let name):
                let presentation = TransitPresentationCatalog.presentation(
                    for: name
                )
                TransitPresentationIcon(
                    presentation: presentation,
                    size: size * 15 / 27,
                    weight: .semibold
                )
                .foregroundStyle(presentation.foregroundColor)
                .frame(width: size, height: size)
                .background(presentation.color, in: .circle)
            case .workout(let systemImageName):
                FixedSizeSymbol(
                    systemName: systemImageName,
                    size: size * 14 / 27,
                    weight: .semibold
                )
                .foregroundStyle(.black)
                .frame(width: size, height: size)
                .background(Color(hex: 0xB6FF00), in: .circle)
            }
        }
    }
}

private struct DaySummaryWakeUpTile: View {
    let wakeUp: DayWakeSummary

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.height < 55 {
                HStack(spacing: 7) {
                    DaySummaryWakeUpIcon()
                    DaySummaryWakeUpLabels(wakeUp: wakeUp)
                }
                .padding(.horizontal, 8)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .leading
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    DaySummaryWakeUpIcon()
                    Spacer(minLength: 4)
                    DaySummaryWakeUpLabels(wakeUp: wakeUp)
                }
                .padding(8)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
            }
        }
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: .rect(cornerRadius: 16)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct DaySummaryWakeUpIcon: View {
    var body: some View {
        FixedSizeSymbol(
            systemName: "sunrise.fill",
            size: 13,
            weight: .semibold
        )
        .foregroundStyle(.white)
        .frame(width: 27, height: 27)
        .background(.cyan.gradient, in: .circle)
    }
}

private struct DaySummaryWakeUpLabels: View {
    let wakeUp: DayWakeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(
                wakeUp.wakeTime,
                format: Date.FormatStyle(
                    date: nil,
                    time: .shortened,
                    timeZone: TimeZone(
                        identifier: wakeUp.timeZoneIdentifier
                    ) ?? .current
                )
            )
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            if let duration = wakeUp.durationSeconds {
                Text(
                    Duration.seconds(duration),
                    format: .units(
                        allowed: [.hours, .minutes],
                        width: .narrow,
                        maximumUnitCount: 2,
                        zeroValueUnits: .hide
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }
}

struct DaySummaryOverviewMap: View {
    let cacheSlotID: String
    let data: TimelineOverviewData
    let loadsContent: Bool

    init(
        cacheSlotID: String,
        data: TimelineOverviewData,
        loadsContent: Bool = true
    ) {
        self.cacheSlotID = cacheSlotID
        self.data = data
        self.loadsContent = loadsContent
    }

    var body: some View {
        SummaryMapSnapshotView(
            cacheSlotID: cacheSlotID,
            data: data,
            loadsContent: loadsContent
        )
        .allowsHitTesting(false)
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityLabel("Map of the day’s places and movement")
    }
}

struct SummaryMapSnapshotView: View {
    let cacheSlotID: String
    let data: TimelineOverviewData
    let loadsContent: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    init(
        cacheSlotID: String,
        data: TimelineOverviewData,
        loadsContent: Bool
    ) {
        self.cacheSlotID = cacheSlotID
        self.data = data
        self.loadsContent = loadsContent
    }

    var body: some View {
        GeometryReader { proxy in
            let request = request(for: proxy.size)
            ZStack {
                Color(uiColor: .secondarySystemGroupedBackground)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .task(id: taskID(for: request)) {
                guard let request else { return }
                if let cached = SummaryMapDecodedImageCache.image(
                    for: request
                ) {
                    image = cached
                    return
                }
                guard loadsContent else { return }
                do {
                    let data = try await SummaryMapSnapshotStore.shared.data(
                        for: request
                    )
                    try Task.checkCancellation()
                    SummaryMapDecodedImageCache.insert(
                        data: data,
                        for: request
                    )
                    image = SummaryMapDecodedImageCache.image(
                        for: request
                    )
                } catch is CancellationError {
                    return
                } catch {
                    image = nil
                }
            }
        }
    }

    private func request(for size: CGSize) -> SummaryMapSnapshotRequest? {
        SummaryMapSnapshotRequestFactory.overview(
            slotID: cacheSlotID,
            data: data,
            size: size,
            displayScale: displayScale,
            appearance: colorScheme == .dark ? .dark : .light
        )
    }

    private func taskID(
        for request: SummaryMapSnapshotRequest?
    ) -> String {
        "\(request?.cacheKey ?? "none")-\(loadsContent)"
    }
}

private struct DaySummaryPlaceMap: View {
    let featuredPlace: DayFeaturedPlace

    var body: some View {
        TimelinePlaceMiniMap(
            location: featuredPlace.location,
            needsReview: featuredPlace.needsReview
        )
    }
}

private struct DaySummaryNeedsReviewTile: View {
    var body: some View {
        HStack(spacing: 10) {
            ReviewBadge(size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("Needs Review")
                    .font(.headline)
                Text("Open this day to finish reviewing its entries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: .rect(cornerRadius: 16)
        )
    }
}
