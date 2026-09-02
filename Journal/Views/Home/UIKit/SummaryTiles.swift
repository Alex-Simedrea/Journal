import SwiftUI
import UIKit

private func summaryFont(
    _ textStyle: UIFont.TextStyle,
    weight: UIFont.Weight = .regular
) -> UIFont {
    let preferred = UIFont.preferredFont(forTextStyle: textStyle)
    return UIFont.systemFont(ofSize: preferred.pointSize, weight: weight)
}

func disableImplicitAnimations(for layer: CALayer) {
    let noAction = NSNull()
    layer.actions = [
        "backgroundColor": noAction,
        "bounds": noAction,
        "colors": noAction,
        "contents": noAction,
        "cornerRadius": noAction,
        "endPoint": noAction,
        "frame": noAction,
        "hidden": noAction,
        "locations": noAction,
        "opacity": noAction,
        "position": noAction,
        "startPoint": noAction,
        "transform": noAction,
    ]
}

private func withoutImplicitAnimations(_ updates: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    updates()
    CATransaction.commit()
}

@MainActor
final class UIKitDaySummaryCanvasView: UIView {
    private var tiles: [DaySummaryTileKind: UIView] = [:]
    private var placements: [DaySummaryTilePlacement] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        disableImplicitAnimations(for: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        model: DaySummaryRowModel,
        loadsDeferredContent: Bool
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        placements = model.layoutRecipe.placements
        let visibleKinds = Set(placements.map(\.tile))
        for (kind, view) in tiles where !visibleKinds.contains(kind) {
            cancelAssets(in: view)
            view.removeFromSuperview()
            tiles[kind] = nil
        }

        for placement in placements {
            let view = tileView(for: placement.tile)
            configure(
                view,
                kind: placement.tile,
                model: model,
                loadsDeferredContent: loadsDeferredContent
            )
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        withoutImplicitAnimations {
            for placement in placements {
                let tile = tiles[placement.tile]
                tile?.frame = placement.frame.cgRect(in: bounds.width)
                tile?.layoutIfNeeded()
            }
        }
    }

    func reset() {
        tiles.values.forEach(cancelAssets)
    }

    private func tileView(for kind: DaySummaryTileKind) -> UIView {
        if let view = tiles[kind] { return view }
        let view: UIView = switch kind {
        case .overview: UIKitSummaryMapImageView(frame: .zero)
        case .weather: UIKitWeatherSummaryTileView()
        case .people: UIKitPeopleSummaryTileView()
        case .photos: UIKitPhotoSummaryTileView()
        case .movement: UIKitMovementSummaryTileView()
        case .wakeUp: UIKitWakeSummaryTileView()
        case .featuredPlace: UIKitPlaceSummaryTileView()
        case .review: UIKitReviewPlaceholderTileView()
        }
        tiles[kind] = view
        addSubview(view)
        return view
    }

    private func configure(
        _ view: UIView,
        kind: DaySummaryTileKind,
        model: DaySummaryRowModel,
        loadsDeferredContent: Bool
    ) {
        switch (kind, view) {
        case let (.overview, map as UIKitSummaryMapImageView):
            map.configure(
                slotID: "day-\(model.id.id)-overview",
                data: model.overviewData,
                // A moving workout's initial projection only contains its
                // endpoints. Do not cache that incomplete map while the exact
                // HealthKit route is being prepared.
                loadsContent: loadsDeferredContent
                    && !model.isWorkoutRouteEnrichmentPending,
                accessibilityLabel: String(localized: "Map of the day’s places and movement")
            )
        case let (.weather, weather as UIKitWeatherSummaryTileView):
            weather.configure(
                state: model.weatherState,
                request: model.summary.weatherRequest
            )
        case let (.people, people as UIKitPeopleSummaryTileView):
            people.configure(
                people: model.summary.people,
                needsReview: model.summary.peopleNeedReview,
                showsCount: false
            )
        case let (.photos, photos as UIKitPhotoSummaryTileView):
            photos.configure(
                references: model.summary.photos,
                totalCount: model.summary.photos.count,
                style: .day,
                loadsContent: true
            )
        case let (.movement, movement as UIKitMovementSummaryTileView):
            if let summary = model.summary.movement {
                movement.configure(summary)
            }
        case let (.wakeUp, wake as UIKitWakeSummaryTileView):
            if let summary = model.summary.wakeUp {
                wake.configure(summary)
            }
        case let (.featuredPlace, place as UIKitPlaceSummaryTileView):
            if let summary = model.summary.featuredPlace {
                place.configure(
                    slotID: "day-\(model.id.id)-featured-place",
                    location: summary.location,
                    footer: nil,
                    needsReview: summary.needsReview,
                    loadsContent: loadsDeferredContent
                )
            }
        case let (.review, review as UIKitReviewPlaceholderTileView):
            review.configure()
        default:
            break
        }
    }
}

@MainActor
final class UIKitPeriodSummaryCanvasView: UIView {
    private var tiles: [PeriodSummaryTileKind: UIView] = [:]
    private var placements: [PeriodSummaryTilePlacement] = []
    private var onOpenDay: ((TimelineDayKey) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        disableImplicitAnimations(for: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        model: PeriodSummaryRowModel,
        loadsDeferredContent: Bool,
        onOpenDay: @escaping (TimelineDayKey) -> Void
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        placements = model.layoutRecipe.placements
        self.onOpenDay = onOpenDay
        let visibleKinds = Set(placements.map(\.tile))
        for (kind, view) in tiles where !visibleKinds.contains(kind) {
            cancelAssets(in: view)
            view.removeFromSuperview()
            tiles[kind] = nil
        }

        for placement in placements {
            let view = tileView(for: placement.tile)
            configure(
                view,
                kind: placement.tile,
                model: model,
                loadsDeferredContent: loadsDeferredContent
            )
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        withoutImplicitAnimations {
            for placement in placements {
                let tile = tiles[placement.tile]
                tile?.frame = placement.frame.cgRect(in: bounds.width)
                tile?.layoutIfNeeded()
            }
        }
    }

    func reset() {
        onOpenDay = nil
        tiles.values.forEach(cancelAssets)
    }

    private func tileView(for kind: PeriodSummaryTileKind) -> UIView {
        if let view = tiles[kind] { return view }
        let view: UIView = switch kind {
        case .overview: UIKitSummaryMapImageView(frame: .zero)
        case .people: UIKitPeopleSummaryTileView()
        case .movement: UIKitPeriodMovementSummaryTileView()
        case .frequentRoute, .longestJourney: UIKitMapCaptionTileView()
        case .place: UIKitPlaceSummaryTileView()
        case .cities, .countries: UIKitGeographySummaryTileView()
        case .photos: UIKitPhotoSummaryTileView()
        case .busiestDay: UIKitPeriodHighlightTileView()
        case .review: UIKitPeriodReviewTileView()
        case .sleep: UIKitPeriodSleepTileView()
        case .newGround: UIKitPeriodNewGroundTileView()
        case .activity: UIKitActivitySummaryTileView()
        }
        tiles[kind] = view
        addSubview(view)
        return view
    }

    private func configure(
        _ view: UIView,
        kind: PeriodSummaryTileKind,
        model: PeriodSummaryRowModel,
        loadsDeferredContent: Bool
    ) {
        let summary = model.summary
        switch (kind, view) {
        case let (.overview, map as UIKitSummaryMapImageView):
            map.configure(
                slotID: "period-\(model.id.id)-overview",
                data: model.overviewData,
                loadsContent: loadsDeferredContent,
                accessibilityLabel: String(localized: "Map of this period")
            )
        case let (.people, people as UIKitPeopleSummaryTileView):
            people.configure(
                people: summary.people.map(\.person),
                needsReview: false,
                showsCount: true
            )
        case let (.movement, movement as UIKitPeriodMovementSummaryTileView):
            if let value = summary.movement { movement.configure(value) }
        case let (.frequentRoute, routeView as UIKitMapCaptionTileView):
            if let route = summary.frequentRoute {
                routeView.configure(
                    slotID: "period-\(model.id.id)-frequent-route",
                    data: model.frequentRouteData ?? route.mapData,
                    loadsContent: loadsDeferredContent,
                    caption: .route(
                        count: route.count,
                        origin: route.originName,
                        destination: route.destinationName
                    ),
                    action: nil
                )
            }
        case let (.place, placeView as UIKitPlaceSummaryTileView):
            if let place = summary.mostVisitedPlace {
                placeView.configure(
                    slotID: "period-\(model.id.id)-place",
                    location: place.location,
                    footer: String(localized: "\(place.visitCount) visits"),
                    needsReview: false,
                    loadsContent: loadsDeferredContent
                )
            }
        case let (.cities, geography as UIKitGeographySummaryTileView):
            geography.configure(values: summary.cities, kind: .cities)
        case let (.countries, geography as UIKitGeographySummaryTileView):
            geography.configure(values: summary.countries, kind: .countries)
        case let (.photos, photos as UIKitPhotoSummaryTileView):
            photos.configure(
                references: summary.photos,
                totalCount: summary.totalPhotoCount,
                style: .period,
                loadsContent: true
            )
        case let (.busiestDay, highlight as UIKitPeriodHighlightTileView):
            if let day = summary.busiestDay {
                highlight.configure(
                    eyebrow: String(localized: "Busiest Day"),
                    title: DaySummaryDatePresentation.dayTitle(for: day),
                    symbol: "flame.fill",
                    tint: .systemOrange,
                    action: { [weak self] in self?.onOpenDay?(day) }
                )
            }
        case let (.longestJourney, journeyView as UIKitMapCaptionTileView):
            if let journey = summary.longestJourney {
                let distance = (journey.distanceMeters / 1_000).formatted(
                    .number.precision(.fractionLength(0...1))
                ) + " km"
                journeyView.configure(
                    slotID: "period-\(model.id.id)-longest-journey",
                    data: model.longestJourneyData ?? journey.mapData,
                    loadsContent: loadsDeferredContent,
                    caption: .journey(
                        distance: distance,
                        origin: journey.originName,
                        destination: journey.destinationName
                    ),
                    action: { [weak self] in self?.onOpenDay?(journey.day) }
                )
            }
        case let (.review, review as UIKitPeriodReviewTileView):
            review.configure(count: summary.reviewCount)
        case let (.sleep, sleepView as UIKitPeriodSleepTileView):
            if let sleep = summary.sleep {
                sleepView.configure(sleep)
            }
        case let (.activity, activity as UIKitActivitySummaryTileView):
            activity.configure(
                values: summary.activity,
                title: summary.monthKey == nil
                    ? String(localized: "Year Rhythm")
                    : String(localized: "Day Rhythm")
            )
        case let (.newGround, newGround as UIKitPeriodNewGroundTileView):
            newGround.configure(count: summary.newGroundCount)
        default:
            break
        }
    }
}

private extension DaySummaryNormalizedFrame {
    func cgRect(in width: CGFloat) -> CGRect {
        CGRect(
            x: x * width,
            y: y * width,
            width: self.width * width,
            height: height * width
        )
    }
}

@MainActor
private func cancelAssets(in view: UIView) {
    (view as? UIKitSummaryMapImageView)?.cancelLoading()
    if let photo = view as? UIKitSummaryPhotoView { photo.reset() }
    if let avatar = view as? UIKitContactAvatarView { avatar.reset() }
    view.subviews.forEach(cancelAssets)
}

@MainActor
class UIKitRoundedSummaryTileView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        disableImplicitAnimations(for: layer)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 16
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class UIKitReviewBadgeView: UIView {
    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        disableImplicitAnimations(for: layer)
        disableImplicitAnimations(for: imageView.layer)
        backgroundColor = .systemOrange
        imageView.image = UIImage(
            systemName: "exclamationmark",
            withConfiguration: UIImage.SymbolConfiguration(weight: .black)
        )
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Needs review")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        withoutImplicitAnimations {
            layer.cornerRadius = bounds.width / 2
            imageView.frame = CGRect(
                x: bounds.width * 7 / 17,
                y: bounds.height * 4 / 17,
                width: bounds.width * 3 / 17,
                height: bounds.height * 9 / 17
            )
        }
    }
}

@MainActor
final class UIKitReviewPlaceholderTileView: UIKitRoundedSummaryTileView {
    private let badge = UIKitReviewBadgeView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.text = String(localized: "Needs Review")
        titleLabel.font = summaryFont(.headline)
        messageLabel.text = String(localized: "Open this day to finish reviewing its entries.")
        messageLabel.font = summaryFont(.caption1)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 2
        [badge, titleLabel, messageLabel].forEach(addSubview)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {}

    override func layoutSubviews() {
        super.layoutSubviews()
        badge.frame = CGRect(x: 12, y: (bounds.height - 20) / 2, width: 20, height: 20)
        let x: CGFloat = 42
        let titleHeight = titleLabel.font.lineHeight
        let messageHeight = min(
            messageLabel.font.lineHeight * 2,
            messageLabel.sizeThatFits(
                CGSize(width: bounds.width - x - 12, height: .greatestFiniteMagnitude)
            ).height
        )
        let groupHeight = titleHeight + 1 + messageHeight
        let groupY = (bounds.height - groupHeight) / 2
        titleLabel.frame = CGRect(
            x: x,
            y: groupY,
            width: bounds.width - x - 12,
            height: titleHeight
        )
        messageLabel.frame = CGRect(
            x: x,
            y: groupY + titleHeight + 1,
            width: bounds.width - x - 12,
            height: messageHeight
        )
    }
}

@MainActor
final class UIKitWeatherSummaryTileView: UIKitRoundedSummaryTileView {
    private let gradient = CAGradientLayer()
    private let symbolView = UIImageView()
    private let temperatureLabel = UILabel()
    private let humidityIconView = UIImageView()
    private let humidityLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let unavailableLabel = UILabel()
    private var weather: DayWeatherSummary?
    private var state: DayWeatherLoadState = .idle
    private var request: DayWeatherRequest?
    private var symbolImageKey = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        disableImplicitAnimations(for: gradient)
        layer.insertSublayer(gradient, at: 0)
        symbolView.contentMode = .scaleAspectFit
        temperatureLabel.textColor = .white
        temperatureLabel.adjustsFontSizeToFitWidth = true
        temperatureLabel.minimumScaleFactor = 0.68
        humidityIconView.contentMode = .scaleAspectFit
        humidityIconView.tintColor = UIColor.white.withAlphaComponent(0.8)
        humidityIconView.image = UIImage(systemName: "humidity.fill")
        humidityLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        humidityLabel.lineBreakMode = .byTruncatingTail
        spinner.color = .white
        unavailableLabel.text = String(localized: "Weather unavailable")
        unavailableLabel.textColor = .white
        unavailableLabel.font = summaryFont(.caption1, weight: .semibold)
        unavailableLabel.numberOfLines = 2
        [
            symbolView,
            temperatureLabel,
            humidityIconView,
            humidityLabel,
            spinner,
            unavailableLabel,
        ].forEach(addSubview)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (view: UIKitWeatherSummaryTileView, _) in
            view.updatePresentation()
        }
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(state: DayWeatherLoadState, request: DayWeatherRequest?) {
        self.state = state
        self.request = request
        weather = state.summary
        updatePresentation()
        setNeedsLayout()
    }

    private func updatePresentation() {
        let symbolName = weather?.symbolName
            ?? (request?.presentationDate == nil ? "cloud.slash.fill" : "sun.max.fill")
        let presentationDate = request?.presentationDate ?? weather?.date ?? .now
        let phase = WeatherPresentation.skyPhase(
            date: presentationDate,
            latitude: request?.latitude,
            longitude: request?.longitude,
            symbolName: symbolName,
            timeZone: TimeZone(identifier: request?.timeZoneIdentifier ?? "") ?? .current
        )
        let colorFactor: CGFloat = traitCollection.userInterfaceStyle == .dark
            ? 0.82 : 1
        gradient.colors = WeatherPresentation.gradientHexes(
            symbolName: symbolName,
            phase: phase
        ).map { UIColor(hex: $0).scaled(by: colorFactor).cgColor }
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)

        if let weather {
            temperatureLabel.text = "\(weather.highTemperatureCelsius.formatted(.number.precision(.fractionLength(0))))°C"
            humidityLabel.text = weather.maximumHumidity.formatted(
                .percent.precision(.fractionLength(0))
            )
            spinner.stopAnimating()
            symbolView.isHidden = false
            temperatureLabel.isHidden = false
            humidityIconView.isHidden = false
            humidityLabel.isHidden = false
            unavailableLabel.isHidden = true
            accessibilityLabel = "\(weather.condition), \(temperatureLabel.text ?? ""), \(humidityLabel.text ?? "")"
        } else {
            symbolView.isHidden = true
            temperatureLabel.isHidden = true
            humidityIconView.isHidden = true
            humidityLabel.isHidden = true
            if state == .idle || state == .loading {
                spinner.startAnimating()
                unavailableLabel.isHidden = true
                accessibilityLabel = String(localized: "Loading weather")
            } else {
                spinner.stopAnimating()
                unavailableLabel.isHidden = false
                accessibilityLabel = unavailableLabel.text
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        let compact = bounds.height < 60
        let padding: CGFloat = compact ? 8 : 10
        if let weather {
            let pointSize: CGFloat = compact ? 26 : 32
            let key = "\(weather.symbolName)|\(pointSize)|\(traitCollection.userInterfaceStyle.rawValue)"
            if key != symbolImageKey {
                symbolImageKey = key
                let swiftUIPalette = WeatherSymbolPalette.colors(
                    for: weather.symbolName
                )
                let palette = [
                    UIColor(swiftUIPalette.primary),
                    UIColor(swiftUIPalette.secondary),
                    UIColor(swiftUIPalette.tertiary),
                ]
                let base = UIImage.SymbolConfiguration(
                    pointSize: pointSize,
                    weight: .semibold
                )
                let colors = UIImage.SymbolConfiguration(paletteColors: palette)
                let filledName = weather.symbolName.hasSuffix(".fill")
                    ? weather.symbolName
                    : weather.symbolName + ".fill"
                symbolView.image = (
                    UIImage(systemName: filledName)
                        ?? UIImage(systemName: weather.symbolName)
                )?.applyingSymbolConfiguration(base.applying(colors))
            }
        }
        spinner.frame = CGRect(
            x: padding,
            y: (bounds.height - 28) / 2,
            width: 28,
            height: 28
        )
        let unavailableHeight = min(
            unavailableLabel.font.lineHeight * 2,
            unavailableLabel.sizeThatFits(
                CGSize(
                    width: bounds.width - padding * 2,
                    height: .greatestFiniteMagnitude
                )
            ).height
        )
        unavailableLabel.frame = CGRect(
            x: padding,
            y: compact
                ? (bounds.height - unavailableHeight) / 2
                : bounds.height - padding - unavailableHeight,
            width: bounds.width - padding * 2,
            height: unavailableHeight
        )
        spinner.transform = compact
            ? CGAffineTransform(scaleX: 0.75, y: 0.75)
            : .identity
        if compact {
            symbolView.frame = CGRect(x: padding, y: (bounds.height - 26) / 2, width: 26, height: 26)
            let labelX: CGFloat = 41
            temperatureLabel.font = summaryFont(.title2, weight: .medium)
            humidityLabel.font = summaryFont(.caption1, weight: .semibold)
            let temperatureHeight = temperatureLabel.font.lineHeight
            let humidityHeight = humidityLabel.font.lineHeight
            let stackHeight = temperatureHeight + humidityHeight
            let stackY = (bounds.height - stackHeight) / 2
            temperatureLabel.frame = CGRect(
                x: labelX,
                y: stackY,
                width: bounds.width - labelX - padding,
                height: temperatureHeight
            )
            let humidityY = stackY + temperatureHeight
            humidityIconView.frame = CGRect(
                x: labelX,
                y: humidityY + (humidityHeight - 13) / 2,
                width: 13,
                height: 13
            )
            humidityLabel.frame = CGRect(
                x: labelX + 16,
                y: humidityY,
                width: bounds.width - labelX - padding - 16,
                height: humidityHeight
            )
        } else {
            let symbolBounds = CGRect(x: padding, y: 8, width: 32, height: 32)
            if let imageSize = symbolView.image?.size,
               imageSize.width > 0,
               imageSize.height > 0 {
                let scale = min(
                    symbolBounds.width / imageSize.width,
                    symbolBounds.height / imageSize.height
                )
                let fittedSize = CGSize(
                    width: imageSize.width * scale,
                    height: imageSize.height * scale
                )
                symbolView.frame = CGRect(
                    x: symbolBounds.midX - fittedSize.width / 2,
                    y: symbolBounds.minY,
                    width: fittedSize.width,
                    height: fittedSize.height
                )
            } else {
                symbolView.frame = symbolBounds
            }
            let titlePointSize = UIFont.preferredFont(
                forTextStyle: .title1
            ).pointSize
            temperatureLabel.font = .systemFont(
                ofSize: max(1, titlePointSize - 1),
                weight: .medium
            )
            humidityLabel.font = summaryFont(.caption1, weight: .semibold)
            let temperatureHeight = temperatureLabel.font.lineHeight
            let humidityHeight = humidityLabel.font.lineHeight
            let humidityY = bounds.height - padding - humidityHeight
            temperatureLabel.frame = CGRect(
                x: padding,
                y: humidityY - temperatureHeight + 2,
                width: bounds.width - padding * 2,
                height: temperatureHeight
            )
            humidityIconView.frame = CGRect(
                x: padding,
                y: humidityY + (humidityHeight - 13) / 2,
                width: 13,
                height: 13
            )
            humidityLabel.frame = CGRect(
                x: padding + 16,
                y: humidityY,
                width: bounds.width - padding * 2 - 16,
                height: humidityHeight
            )
        }
    }

}

@MainActor
final class UIKitPeopleSummaryTileView: UIKitRoundedSummaryTileView {
    private let countLabel = UILabel()
    private let reviewBadge = UIKitReviewBadgeView()
    private var avatarViews: [UIKitContactAvatarView] = []
    private var people: [TimelinePersonSnapshot] = []
    private var showsCount = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        countLabel.font = summaryFont(.caption2, weight: .semibold)
        countLabel.textColor = .secondaryLabel
        countLabel.textAlignment = .center
        addSubview(countLabel)
        addSubview(reviewBadge)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        people: [TimelinePersonSnapshot],
        needsReview: Bool,
        showsCount: Bool
    ) {
        self.people = Array(people.prefix(showsCount ? 18 : 12))
        self.showsCount = showsCount
        while avatarViews.count < self.people.count {
            let view = UIKitContactAvatarView()
            avatarViews.append(view)
            insertSubview(view, belowSubview: countLabel)
        }
        for (index, view) in avatarViews.enumerated() {
            view.isHidden = index >= self.people.count
            if index < self.people.count {
                view.configure(person: self.people[index])
            }
        }
        countLabel.isHidden = !showsCount
        countLabel.text = String(localized: "\(people.count) people")
        reviewBadge.isHidden = !needsReview
        accessibilityLabel = showsCount
            ? countLabel.text
            : people.map(\.name).formatted(.list(type: .and, width: .short))
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let labelHeight: CGFloat = showsCount ? (bounds.height < 90 ? 18 : 20) : 0
        let verticalPadding: CGFloat = showsCount ? (bounds.height < 90 ? 3 : 6) : 4
        let contentHeight = max(0, bounds.height - labelHeight - verticalPadding * 2)
        let placements = EntryDetailPeopleConstellationMetrics.placements(
            count: people.count
        )
        countLabel.frame = CGRect(
            x: 0,
            y: bounds.height - 5 - countLabel.font.lineHeight,
            width: bounds.width,
            height: countLabel.font.lineHeight
        )
        reviewBadge.frame = CGRect(x: bounds.width - 19, y: 4, width: 15, height: 15)
        guard !placements.isEmpty else { return }
        let widthScale = EntryDetailPeopleConstellationMetrics.scale(
            for: bounds.width - (showsCount ? 12 : 0),
            placements: placements
        )
        let heightScale = contentHeight
            / EntryDetailPeopleConstellationMetrics.height
        let scale = min(widthScale, heightScale)
        for index in people.indices {
            let placement = placements[index]
            let diameter = placement.diameter * scale
            avatarViews[index].frame = CGRect(
                x: bounds.midX + placement.center.x * scale - diameter / 2,
                y: verticalPadding + contentHeight / 2
                    + placement.center.y * scale - diameter / 2,
                width: diameter,
                height: diameter
            )
        }
    }
}

@MainActor
final class UIKitContactAvatarView: UIView {
    private let imageView = UIImageView()
    private let monogramLabel = UILabel()
    private let gradient = CAGradientLayer()
    private var representedIdentifier: String?
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        disableImplicitAnimations(for: gradient)
        disableImplicitAnimations(for: layer)
        layer.insertSublayer(gradient, at: 0)
        gradient.colors = [
            UIColor(red: 197 / 255, green: 213 / 255, blue: 233 / 255, alpha: 1).cgColor,
            UIColor(red: 155 / 255, green: 166 / 255, blue: 205 / 255, alpha: 1).cgColor,
        ]
        imageView.contentMode = .scaleAspectFill
        disableImplicitAnimations(for: imageView.layer)
        imageView.clipsToBounds = true
        monogramLabel.textColor = .white
        monogramLabel.textAlignment = .center
        addSubview(imageView)
        addSubview(monogramLabel)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(person: TimelinePersonSnapshot) {
        monogramLabel.text = PersonMonogram.initials(for: person.name)
        monogramLabel.isHidden = imageView.image != nil
        accessibilityLabel = imageView.image == nil
            ? String(localized: "Monogram for \(person.name)")
            : String(localized: "Contact photo for \(person.name)")
        guard representedIdentifier != person.contactIdentifier else { return }
        representedIdentifier = person.contactIdentifier
        loadTask?.cancel()
        imageView.image = nil
        monogramLabel.isHidden = false
        guard let identifier = person.contactIdentifier else { return }
        loadTask = Task { [weak self] in
            let cached = await UIKitContactAvatarStore.shared.cachedImage(
                for: identifier
            )
            let image: UIImage?
            if let cached {
                image = cached
            } else {
                image = await UIKitContactAvatarStore.shared.image(
                    for: identifier
                )
            }
            guard !Task.isCancelled,
                  self?.representedIdentifier == identifier else { return }
            self?.imageView.image = image
            self?.monogramLabel.isHidden = image != nil
            self?.accessibilityLabel = image == nil
                ? String(localized: "Monogram for \(person.name)")
                : String(localized: "Contact photo for \(person.name)")
        }
    }

    func reset() {
        representedIdentifier = nil
        loadTask?.cancel()
        loadTask = nil
        imageView.image = nil
        monogramLabel.isHidden = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        clipsToBounds = true
        gradient.frame = bounds
        imageView.frame = bounds
        imageView.layer.cornerRadius = bounds.width / 2
        monogramLabel.frame = bounds
        monogramLabel.font = .systemFont(
            ofSize: bounds.width * 0.38,
            weight: .semibold
        )
    }
}

@MainActor
final class UIKitPhotoSummaryTileView: UIView {
    enum Style { case day, period }

    private var imageViews: [UIKitSummaryPhotoView] = []
    private let overflowLabel = UILabel()
    private var references: [PhotoReference] = []
    private var totalCount = 0
    private var style: Style = .day

    override init(frame: CGRect) {
        super.init(frame: frame)
        disableImplicitAnimations(for: layer)
        disableImplicitAnimations(for: overflowLabel.layer)
        overflowLabel.backgroundColor = UIColor.black.withAlphaComponent(0.48)
        overflowLabel.textColor = .white
        overflowLabel.font = .preferredFont(forTextStyle: .headline)
        overflowLabel.textAlignment = .center
        overflowLabel.isHidden = true
        addSubview(overflowLabel)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        references: [PhotoReference],
        totalCount: Int,
        style: Style,
        loadsContent: Bool
    ) {
        self.references = Array(references.prefix(4))
        self.totalCount = totalCount
        self.style = style
        while imageViews.count < self.references.count {
            let view = UIKitSummaryPhotoView(frame: .zero)
            imageViews.append(view)
            insertSubview(view, belowSubview: overflowLabel)
        }
        for (index, view) in imageViews.enumerated() {
            view.isHidden = index >= self.references.count
            if index < self.references.count {
                view.configure(
                    reference: self.references[index],
                    cornerRadius: self.references.count == 1
                        ? (style == .day ? 16 : 18)
                        : (style == .day ? 10 : 14),
                    loadsContent: loadsContent
                )
            }
        }
        overflowLabel.isHidden = style != .day || totalCount <= 4
        overflowLabel.text = totalCount > 4 ? "+\(totalCount - 4)" : nil
        accessibilityLabel = String(localized: "\(totalCount) photos")
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !references.isEmpty else { return }
        let frames = style == .day ? dayFrames() : periodFrames()
        for (index, frame) in frames.enumerated() {
            imageViews[index].frame = frame
        }
        if !overflowLabel.isHidden, frames.indices.contains(3) {
            overflowLabel.frame = frames[3]
            overflowLabel.layer.cornerRadius = 10
            overflowLabel.clipsToBounds = true
        }
    }

    private func dayFrames() -> [CGRect] {
        let gap: CGFloat = 6
        let columns = references.count == 1 ? 1 : 2
        let rows = references.count >= 3 ? 2 : 1
        let width = (bounds.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let height = (bounds.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        return references.indices.map { index in
            CGRect(
                x: CGFloat(index % columns) * (width + gap),
                y: CGFloat(index / columns) * (height + gap),
                width: width,
                height: height
            )
        }
    }

    private func periodFrames() -> [CGRect] {
        let gap: CGFloat = 6
        let metrics = UIKitPeriodPhotoGridMetrics.best(
            itemCount: references.count,
            size: bounds.size,
            gap: gap
        )
        let contentWidth = metrics.side * CGFloat(metrics.columns)
            + gap * CGFloat(max(0, metrics.columns - 1))
        let contentHeight = metrics.side * CGFloat(metrics.rows)
            + gap * CGFloat(max(0, metrics.rows - 1))
        let origin = CGPoint(
            x: (bounds.width - contentWidth) / 2,
            y: (bounds.height - contentHeight) / 2
        )
        return references.indices.map { index in
            CGRect(
                x: origin.x + CGFloat(index % metrics.columns) * (metrics.side + gap),
                y: origin.y + CGFloat(index / metrics.columns) * (metrics.side + gap),
                width: metrics.side,
                height: metrics.side
            )
        }
    }
}

private struct UIKitPeriodPhotoGridMetrics {
    let columns: Int
    let rows: Int
    let side: CGFloat

    static func best(itemCount: Int, size: CGSize, gap: CGFloat) -> Self {
        guard itemCount > 0 else { return Self(columns: 1, rows: 1, side: 0) }
        return (1...itemCount).map { columns in
            let rows = Int(ceil(Double(itemCount) / Double(columns)))
            return Self(
                columns: columns,
                rows: rows,
                side: max(0, min(
                    (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns),
                    (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
                ))
            )
        }.max {
            if abs($0.side - $1.side) > 3 { return $0.side < $1.side }
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

@MainActor
final class UIKitMovementSummaryTileView: UIKitRoundedSummaryTileView {
    private var badgeViews: [UIKitMovementBadgeView] = []
    private let metricsLabel = UILabel()
    private let reviewBadge = UIKitReviewBadgeView()
    private var movement: DayMovementSummary?

    override init(frame: CGRect) {
        super.init(frame: frame)
        metricsLabel.textColor = .secondaryLabel
        metricsLabel.adjustsFontSizeToFitWidth = true
        metricsLabel.minimumScaleFactor = 0.7
        metricsLabel.numberOfLines = 1
        addSubview(metricsLabel)
        addSubview(reviewBadge)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ movement: DayMovementSummary) {
        self.movement = movement
        let maximumVisibleCount = min(movement.icons.count, 5)
        while badgeViews.count < maximumVisibleCount {
            let badge = UIKitMovementBadgeView()
            badgeViews.append(badge)
            insertSubview(badge, belowSubview: metricsLabel)
        }
        for (index, badge) in badgeViews.enumerated() {
            badge.isHidden = index >= movement.icons.count
            if index < movement.icons.count {
                badge.configure(movement.icons[index])
            }
        }
        metricsLabel.text = Self.metricsText(for: movement)
        reviewBadge.isHidden = !movement.needsReview
        accessibilityLabel = metricsLabel.text
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let movement else { return }
        let compact = bounds.height < DaySummaryLayoutRecipe.movementExpansionThreshold
        metricsLabel.text = compact
            ? Self.distanceText(for: movement)
            : Self.metricsText(for: movement)
        let maximum: CGFloat = compact ? 27 : 30
        let count = min(movement.icons.count, compact ? 2 : 5)
        let availableWidth = max(0, bounds.width - 16)
        let size = count == 0
            ? maximum
            : min(maximum, availableWidth * 2 / CGFloat(count + 1))
        for index in badgeViews.indices {
            badgeViews[index].isHidden = index >= count
            if index < count {
                badgeViews[index].frame = CGRect(
                    x: 8 + CGFloat(index) * size / 2,
                    y: compact ? (bounds.height - size) / 2 : 9,
                    width: size,
                    height: size
                )
            }
        }
        if compact {
            let badgesWidth = count == 0 ? 0 : size + CGFloat(count - 1) * size / 2
            metricsLabel.font = summaryFont(.subheadline, weight: .medium)
            metricsLabel.textAlignment = .right
            metricsLabel.frame = CGRect(
                x: 8 + badgesWidth,
                y: 0,
                width: max(0, bounds.width - badgesWidth - 16),
                height: bounds.height
            )
        } else {
            metricsLabel.font = summaryFont(.subheadline)
            metricsLabel.textAlignment = .left
            let lineHeight = metricsLabel.font.lineHeight
            metricsLabel.frame = CGRect(
                x: 8,
                y: bounds.height - 9 - lineHeight,
                width: bounds.width - 16,
                height: lineHeight
            )
        }
        reviewBadge.frame = CGRect(x: bounds.width - 19, y: 4, width: 15, height: 15)
    }

    private static func metricsText(for movement: DayMovementSummary) -> String? {
        let distance = distanceText(for: movement)
        let duration: String? = movement.durationSeconds.map { seconds in
            let totalMinutes = Int(seconds.rounded()) / 60
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if hours > 0 { return minutes > 0 ? "\(hours)h\(minutes)m" : "\(hours)h" }
            return "\(minutes)m"
        }
        return [distance, duration].compactMap { $0 }.joined(separator: " · ")
    }

    private static func distanceText(for movement: DayMovementSummary) -> String? {
        movement.distanceMeters.map { meters in
            let kilometers = meters / 1_000
            let precision: FloatingPointFormatStyle<Double>.Configuration.Precision =
                kilometers < 10 ? .fractionLength(0...1) : .fractionLength(0)
            return kilometers.formatted(.number.precision(precision)) + "km"
        }
    }
}

@MainActor
final class UIKitPeriodMovementSummaryTileView: UIKitRoundedSummaryTileView {
    private var badgeViews: [UIKitMovementBadgeView] = []
    private let metricsLabel = UILabel()
    private var movement: DayMovementSummary?

    override init(frame: CGRect) {
        super.init(frame: frame)
        metricsLabel.font = summaryFont(.subheadline, weight: .semibold)
        metricsLabel.textColor = .label
        metricsLabel.adjustsFontSizeToFitWidth = true
        metricsLabel.minimumScaleFactor = 0.75
        metricsLabel.allowsDefaultTighteningForTruncation = true
        metricsLabel.numberOfLines = 1
        addSubview(metricsLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ movement: DayMovementSummary) {
        self.movement = movement
        let visibleCount = min(movement.icons.count, 9)
        while badgeViews.count < visibleCount {
            let badge = UIKitMovementBadgeView()
            badgeViews.append(badge)
            insertSubview(badge, belowSubview: metricsLabel)
        }
        for (index, badge) in badgeViews.enumerated() {
            badge.isHidden = index >= visibleCount
            if index < visibleCount { badge.configure(movement.icons[index]) }
        }
        metricsLabel.text = Self.metrics(for: movement)
        accessibilityLabel = metricsLabel.text
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let movement else { return }
        let count = min(movement.icons.count, 9)
        let badgeSize = min(36, max(28, bounds.height * 0.42))
        for index in badgeViews.indices {
            badgeViews[index].isHidden = index >= count
            if index < count {
                badgeViews[index].frame = CGRect(
                    x: 8 + CGFloat(index) * badgeSize / 2,
                    y: 8,
                    width: badgeSize,
                    height: badgeSize
                )
            }
        }
        let lineHeight = metricsLabel.font.lineHeight
        metricsLabel.frame = CGRect(
            x: 8,
            y: bounds.height - 8 - lineHeight,
            width: bounds.width - 16,
            height: lineHeight
        )
    }

    private static func metrics(for movement: DayMovementSummary) -> String {
        let distance = movement.distanceMeters.map {
            ($0 / 1_000).formatted(
                .number.precision(.fractionLength(0...1))
            ) + " km"
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

@MainActor
final class UIKitMovementBadgeView: UIView {
    private let imageView = UIImageView()
    private var isWorkout = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        disableImplicitAnimations(for: layer)
        disableImplicitAnimations(for: imageView.layer)
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ icon: DayMovementIcon) {
        switch icon.kind {
        case .transit(let name):
            isWorkout = false
            let presentation = TransitPresentationCatalog.presentation(for: name)
            backgroundColor = UIColor(presentation.color)
            imageView.tintColor = UIColor(presentation.foregroundColor)
            if let brand = presentation.brandImage {
                imageView.image = UIImage(named: brand.rawValue)
            } else {
                imageView.image = UIImage(
                    systemName: presentation.systemImageName,
                    withConfiguration: UIImage.SymbolConfiguration(weight: .semibold)
                )
            }
        case .workout(let systemImage):
            isWorkout = true
            backgroundColor = UIColor(hex: 0xB6FF00)
            imageView.tintColor = .black
            imageView.image = UIImage(
                systemName: systemImage,
                withConfiguration: UIImage.SymbolConfiguration(weight: .semibold)
            )
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        withoutImplicitAnimations {
            layer.cornerRadius = bounds.width / 2
            let side = bounds.width * (isWorkout ? 14 : 15) / 27
            imageView.frame = CGRect(
                x: (bounds.width - side) / 2,
                y: (bounds.height - side) / 2,
                width: side,
                height: side
            )
        }
    }
}

@MainActor
final class UIKitWakeSummaryTileView: UIKitRoundedSummaryTileView {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private let iconBackground = UIView()
    private let iconGradient = CAGradientLayer()
    private let iconView = UIImageView()
    private let timeLabel = UILabel()
    private let durationLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        disableImplicitAnimations(for: iconBackground.layer)
        disableImplicitAnimations(for: iconView.layer)
        iconBackground.layer.addSublayer(iconGradient)
        disableImplicitAnimations(for: iconGradient)
        iconGradient.colors = [
            UIColor.systemCyan.scaled(by: 1.08).cgColor,
            UIColor.systemCyan.scaled(by: 0.82).cgColor,
        ]
        iconGradient.startPoint = CGPoint(x: 0.5, y: 0)
        iconGradient.endPoint = CGPoint(x: 0.5, y: 1)
        iconView.image = UIImage(
            systemName: "sunrise.fill",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 13,
                weight: .semibold
            )
        )
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        timeLabel.font = summaryFont(.subheadline, weight: .semibold)
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.minimumScaleFactor = 0.7
        durationLabel.font = summaryFont(.caption2)
        durationLabel.textColor = .secondaryLabel
        [iconBackground, iconView, timeLabel, durationLabel].forEach(addSubview)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ wake: DayWakeSummary) {
        Self.timeFormatter.timeZone = TimeZone(
            identifier: wake.timeZoneIdentifier
        ) ?? .current
        timeLabel.text = Self.timeFormatter.string(from: wake.wakeTime)
        durationLabel.text = wake.durationSeconds.map {
            Duration.seconds($0).formatted(.units(
                allowed: [.hours, .minutes],
                width: .narrow,
                maximumUnitCount: 2,
                zeroValueUnits: .hide
            ))
        }
        durationLabel.isHidden = durationLabel.text == nil
        accessibilityLabel = [timeLabel.text, durationLabel.text]
            .compactMap { $0 }.joined(separator: ", ")
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let compact = bounds.height < 55
        iconBackground.frame = CGRect(
            x: 8,
            y: compact ? (bounds.height - 27) / 2 : 8,
            width: 27,
            height: 27
        )
        iconBackground.layer.cornerRadius = 13.5
        iconBackground.clipsToBounds = true
        iconGradient.frame = iconBackground.bounds
        iconView.frame = iconBackground.frame.insetBy(dx: 7, dy: 7)
        let timeHeight = timeLabel.font.lineHeight
        let durationHeight = durationLabel.isHidden
            ? 0
            : durationLabel.font.lineHeight
        let labelsHeight = timeHeight + durationHeight
        if compact {
            let labelsY = (bounds.height - labelsHeight) / 2
            timeLabel.frame = CGRect(
                x: 42,
                y: labelsY,
                width: bounds.width - 50,
                height: timeHeight
            )
            durationLabel.frame = CGRect(
                x: 42,
                y: labelsY + timeHeight,
                width: bounds.width - 50,
                height: durationHeight
            )
        } else {
            let labelsY = bounds.height - 8 - labelsHeight
            timeLabel.frame = CGRect(
                x: 8,
                y: labelsY,
                width: bounds.width - 16,
                height: timeHeight
            )
            durationLabel.frame = CGRect(
                x: 8,
                y: labelsY + timeHeight,
                width: bounds.width - 16,
                height: durationHeight
            )
        }
    }
}

@MainActor
final class UIKitPlaceSummaryTileView: UIView {
    private let mapView = UIKitSummaryMapImageView(frame: .zero)
    private let footerLabel = UILabel()
    private let footerGradient = CAGradientLayer()
    private let reviewBadge = UIKitReviewBadgeView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        disableImplicitAnimations(for: layer)
        disableImplicitAnimations(for: footerGradient)
        clipsToBounds = true
        layer.cornerRadius = 16
        addSubview(mapView)
        layer.addSublayer(footerGradient)
        footerGradient.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.24).cgColor,
            UIColor.black.withAlphaComponent(0.68).cgColor,
        ]
        footerGradient.locations = [0, 0.48, 1]
        footerGradient.startPoint = CGPoint(x: 0.5, y: 0)
        footerGradient.endPoint = CGPoint(x: 0.5, y: 1)
        footerLabel.textColor = .white
        footerLabel.font = summaryFont(.caption2, weight: .semibold)
        addSubview(footerLabel)
        addSubview(reviewBadge)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        slotID: String,
        location: TimelineLocationSnapshot,
        footer: String?,
        needsReview: Bool,
        loadsContent: Bool
    ) {
        mapView.configurePlace(
            slotID: slotID,
            location: location,
            loadsContent: loadsContent,
            accessibilityLabel: location.name
        )
        footerLabel.text = footer
        footerLabel.isHidden = footer == nil
        footerGradient.isHidden = footer == nil
        reviewBadge.isHidden = !needsReview
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        mapView.frame = bounds
        footerGradient.frame = CGRect(
            x: 0,
            y: bounds.height - 42,
            width: bounds.width,
            height: 42
        )
        footerLabel.frame = CGRect(x: 7, y: bounds.height - 21, width: bounds.width - 14, height: 14)
        reviewBadge.frame = CGRect(x: bounds.width - 22, y: 5, width: 17, height: 17)
    }
}

@MainActor
final class UIKitMapCaptionTileView: UIControl {
    enum Caption {
        case route(count: Int, origin: String, destination: String)
        case journey(distance: String, origin: String, destination: String)
    }

    private let mapView = UIKitSummaryMapImageView(frame: .zero)
    private let captionGradient = CAGradientLayer()
    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private let destinationLabel = UILabel()
    private var action: (() -> Void)?
    private var caption: Caption?

    override init(frame: CGRect) {
        super.init(frame: frame)
        disableImplicitAnimations(for: layer)
        disableImplicitAnimations(for: captionGradient)
        clipsToBounds = true
        layer.cornerRadius = 16
        addSubview(mapView)
        layer.addSublayer(captionGradient)
        captionGradient.locations = [0, 0.42, 1]
        captionGradient.startPoint = CGPoint(x: 0.5, y: 0)
        captionGradient.endPoint = CGPoint(x: 0.5, y: 1)
        eyebrowLabel.textColor = UIColor.white.withAlphaComponent(0.84)
        eyebrowLabel.numberOfLines = 1
        eyebrowLabel.adjustsFontSizeToFitWidth = true
        eyebrowLabel.minimumScaleFactor = 0.7
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7
        destinationLabel.textColor = .white
        destinationLabel.numberOfLines = 1
        destinationLabel.adjustsFontSizeToFitWidth = true
        destinationLabel.minimumScaleFactor = 0.7
        addSubview(eyebrowLabel)
        addSubview(titleLabel)
        addSubview(destinationLabel)
        addTarget(self, action: #selector(runAction), for: .touchUpInside)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        slotID: String,
        data: TimelineOverviewData,
        loadsContent: Bool,
        caption: Caption,
        action: (() -> Void)?
    ) {
        self.caption = caption
        updateCaptionGradient(for: caption)
        mapView.configure(
            slotID: slotID,
            data: data,
            loadsContent: loadsContent,
            accessibilityLabel: caption.accessibilityLabel
        )
        self.action = action
        isUserInteractionEnabled = action != nil
        accessibilityTraits = action == nil ? .image : .button
        accessibilityLabel = caption.accessibilityLabel
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        mapView.frame = bounds
        let compact = bounds.width < 130
        let captionHeight: CGFloat = compact ? 66 : 50
        captionGradient.frame = CGRect(
            x: 0,
            y: bounds.height - captionHeight,
            width: bounds.width,
            height: captionHeight
        )
        guard let caption else { return }
        if compact {
            eyebrowLabel.font = summaryFont(.caption2, weight: .semibold)
            titleLabel.font = summaryFont(.caption1, weight: .semibold)
            destinationLabel.font = summaryFont(.caption1, weight: .semibold)
            switch caption {
            case let .route(count, origin, destination):
                eyebrowLabel.text = String(localized: "\(count)× route")
                titleLabel.text = origin
                destinationLabel.text = "↓ \(destination)"
                eyebrowLabel.textColor = UIColor.white.withAlphaComponent(0.84)
            case let .journey(distance, origin, destination):
                eyebrowLabel.text = distance
                titleLabel.text = origin
                destinationLabel.text = "↓ \(destination)"
                eyebrowLabel.textColor = UIColor.white.withAlphaComponent(0.86)
            }
            let eyebrowHeight = eyebrowLabel.font.lineHeight
            let titleHeight = titleLabel.font.lineHeight
            let destinationHeight = destinationLabel.font.lineHeight
            let contentHeight = eyebrowHeight + 1 + titleHeight + 1
                + destinationHeight
            let y = bounds.height - contentHeight - 7
            eyebrowLabel.frame = CGRect(
                x: 7,
                y: y,
                width: bounds.width - 14,
                height: eyebrowHeight
            )
            titleLabel.frame = CGRect(
                x: 7,
                y: y + eyebrowHeight + 1,
                width: bounds.width - 14,
                height: titleHeight
            )
            destinationLabel.frame = CGRect(
                x: 7,
                y: titleLabel.frame.maxY + 1,
                width: bounds.width - 14,
                height: destinationHeight
            )
        } else {
            destinationLabel.isHidden = true
            eyebrowLabel.font = summaryFont(.caption1, weight: .semibold)
            switch caption {
            case let .route(count, origin, destination):
                eyebrowLabel.text = String(localized: "Favorite route · \(count) times")
                eyebrowLabel.textColor = UIColor.white.withAlphaComponent(0.82)
                titleLabel.text = "\(origin) ↔ \(destination)"
                titleLabel.font = summaryFont(.subheadline, weight: .semibold)
            case let .journey(distance, origin, destination):
                eyebrowLabel.text = String(localized: "Longest journey · \(distance)")
                eyebrowLabel.textColor = UIColor.white.withAlphaComponent(0.86)
                titleLabel.text = "\(origin) → \(destination)"
                titleLabel.font = summaryFont(.caption1, weight: .semibold)
            }
            let eyebrowHeight = eyebrowLabel.font.lineHeight
            let titleHeight = titleLabel.font.lineHeight
            let spacing: CGFloat = switch caption {
            case .route: 1
            case .journey: 0
            }
            let contentHeight = eyebrowHeight + spacing + titleHeight
            let y = bounds.height - contentHeight - 8
            eyebrowLabel.frame = CGRect(
                x: 8,
                y: y,
                width: bounds.width - 16,
                height: eyebrowHeight
            )
            titleLabel.frame = CGRect(
                x: 8,
                y: y + eyebrowHeight + spacing,
                width: bounds.width - 16,
                height: titleHeight
            )
        }
        if compact { destinationLabel.isHidden = false }
    }

    private func updateCaptionGradient(for caption: Caption) {
        let bottomAlpha: CGFloat = switch caption {
        case .route: 0.72
        case .journey: 0.78
        }
        captionGradient.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.28).cgColor,
            UIColor.black.withAlphaComponent(bottomAlpha).cgColor,
        ]
    }

    @objc private func runAction() { action?() }
}

private extension UIKitMapCaptionTileView.Caption {
    var accessibilityLabel: String {
        switch self {
        case let .route(count, origin, destination):
            String(localized: "Most frequent route, \(count) times from \(origin) to \(destination)")
        case let .journey(distance, origin, destination):
            String(localized: "Longest journey, \(distance), from \(origin) to \(destination)")
        }
    }
}

@MainActor
final class UIKitGeographySummaryTileView: UIKitRoundedSummaryTileView {
    enum Kind { case cities, countries }

    private var bubbleViews: [UIView] = []
    private var bubbleLabels: [UILabel] = []
    private var bubbleGradients: [CAGradientLayer] = []
    private let countLabel = UILabel()
    private var values: [PeriodGeographySummary] = []
    private var kind: Kind = .cities

    override init(frame: CGRect) {
        super.init(frame: frame)
        countLabel.font = summaryFont(.caption2, weight: .semibold)
        countLabel.textColor = .secondaryLabel
        countLabel.textAlignment = .center
        addSubview(countLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(values: [PeriodGeographySummary], kind: Kind) {
        self.values = Array(values.prefix(3))
        self.kind = kind
        while bubbleLabels.count < self.values.count {
            let bubble = UIView()
            disableImplicitAnimations(for: bubble.layer)
            bubble.clipsToBounds = true
            let label = UILabel()
            label.textAlignment = .center
            let gradient = CAGradientLayer()
            disableImplicitAnimations(for: gradient)
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
            bubble.layer.addSublayer(gradient)
            bubble.addSubview(label)
            bubbleViews.append(bubble)
            bubbleLabels.append(label)
            bubbleGradients.append(gradient)
            insertSubview(bubble, belowSubview: countLabel)
        }
        for (index, label) in bubbleLabels.enumerated() {
            bubbleViews[index].isHidden = index >= self.values.count
            guard index < self.values.count else { continue }
            let value = self.values[index]
            label.text = kind == .countries
                ? Self.flag(for: value.code)
                : String(value.name.prefix(3)).uppercased()
            label.font = kind == .countries
                ? summaryFont(.caption1)
                : .systemFont(ofSize: 8, weight: .bold)
            label.textColor = kind == .countries ? .label : .white
            label.backgroundColor = .clear
            bubbleGradients[index].colors = Self.colors(for: value.name)
        }
        let total = values.count
        countLabel.text = switch kind {
        case .cities: total == 1 ? String(localized: "1 city") : String(localized: "\(total) cities")
        case .countries: total == 1 ? String(localized: "1 country") : String(localized: "\(total) countries")
        }
        accessibilityLabel = countLabel.text
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 25
        let overlap: CGFloat = 3
        let width = values.isEmpty ? 0 : side * CGFloat(values.count)
            - overlap * CGFloat(max(0, values.count - 1))
        let startX = (bounds.width - width) / 2
        let labelHeight = countLabel.font.lineHeight
        let groupHeight = side + 5 + labelHeight
        let groupY = (bounds.height - groupHeight) / 2
        for index in values.indices {
            bubbleViews[index].frame = CGRect(
                x: startX + CGFloat(index) * (side - overlap),
                y: groupY,
                width: side,
                height: side
            )
            bubbleViews[index].layer.cornerRadius = side / 2
            bubbleLabels[index].frame = bubbleViews[index].bounds
            bubbleGradients[index].frame = bubbleViews[index].bounds
            bubbleGradients[index].cornerRadius = side / 2
        }
        countLabel.frame = CGRect(
            x: 4,
            y: groupY + side + 5,
            width: bounds.width - 8,
            height: labelHeight
        )
    }

    private static func colors(for value: String) -> [CGColor] {
        let seed = value.uppercased().unicodeScalars.reduce(UInt64(1_469_598_103_934_665_603)) {
            ($0 ^ UInt64($1.value)) &* 1_099_511_628_211
        }
        let hue = CGFloat(seed % 360) / 360
        let saturation = 0.42 + CGFloat((seed >> 9) % 12) / 100
        let brightness = 0.72 + CGFloat((seed >> 17) % 10) / 100
        return [
            UIColor(
                hue: hue,
                saturation: max(0.2, saturation - 0.08),
                brightness: min(0.92, brightness + 0.12),
                alpha: 1
            ).cgColor,
            UIColor(
                hue: hue,
                saturation: min(0.68, saturation + 0.08),
                brightness: max(0.48, brightness - 0.14),
                alpha: 1
            ).cgColor,
        ]
    }

    private static func flag(for code: String?) -> String {
        guard let code, code.count == 2 else { return "🌐" }
        return code.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127_397 + $0.value).map(String.init)
        }.joined()
    }
}

@MainActor
final class UIKitPeriodHighlightTileView: UIControl {
    private let symbolView = UIImageView()
    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private var action: (() -> Void)?
    private var symbolName = ""
    private var configuredSymbolPointSize: CGFloat = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        disableImplicitAnimations(for: layer)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 16
        clipsToBounds = true
        symbolView.contentMode = .scaleAspectFit
        eyebrowLabel.textColor = .secondaryLabel
        eyebrowLabel.numberOfLines = 1
        eyebrowLabel.adjustsFontSizeToFitWidth = true
        eyebrowLabel.minimumScaleFactor = 0.72
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.72
        [symbolView, eyebrowLabel, titleLabel].forEach(addSubview)
        addTarget(self, action: #selector(runAction), for: .touchUpInside)
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        eyebrow: String,
        title: String,
        symbol: String,
        tint: UIColor,
        action: @escaping () -> Void
    ) {
        eyebrowLabel.text = eyebrow
        titleLabel.text = title
        symbolName = symbol
        configuredSymbolPointSize = -1
        symbolView.image = UIImage(systemName: symbol)
        symbolView.tintColor = tint
        self.action = action
        accessibilityLabel = eyebrow + ", " + title
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let compact = bounds.height < 76
        let padding: CGFloat = compact ? 7 : 9
        eyebrowLabel.font = summaryFont(
            compact ? .caption2 : .caption1,
            weight: .semibold
        )
        let eyebrowHeight = eyebrowLabel.font.lineHeight
        let symbolPointSize = UIFont.preferredFont(
            forTextStyle: compact ? .caption2 : .caption1
        ).pointSize
        if configuredSymbolPointSize != symbolPointSize {
            configuredSymbolPointSize = symbolPointSize
            symbolView.image = UIImage(
                systemName: symbolName,
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: symbolPointSize,
                    weight: .semibold
                )
            )
        }
        let iconSize = symbolView.image?.size ?? CGSize(
            width: symbolPointSize,
            height: symbolPointSize
        )
        symbolView.frame = CGRect(
            x: padding,
            y: padding + (eyebrowHeight - iconSize.height) / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        eyebrowLabel.frame = CGRect(
            x: symbolView.frame.maxX + 4,
            y: padding,
            width: bounds.width - padding - symbolView.frame.maxX - 4,
            height: eyebrowHeight
        )
        titleLabel.font = summaryFont(
            compact ? .caption1 : .subheadline,
            weight: .semibold
        )
        let titleHeight = min(
            titleLabel.font.lineHeight * 2,
            titleLabel.sizeThatFits(
                CGSize(
                    width: bounds.width - padding * 2,
                    height: .greatestFiniteMagnitude
                )
            ).height
        )
        titleLabel.frame = CGRect(
            x: padding,
            y: bounds.height - padding - titleHeight,
            width: bounds.width - padding * 2,
            height: titleHeight
        )
    }

    @objc private func runAction() { action?() }
}

@MainActor
final class UIKitPeriodReviewTileView: UIKitRoundedSummaryTileView {
    private let badge = UIKitReviewBadgeView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = summaryFont(.subheadline, weight: .semibold)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        [badge, label].forEach(addSubview)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(count: Int) {
        label.text = String(localized: "\(count) Needs Review")
        accessibilityLabel = label.text
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.height > bounds.width * 0.92 {
            let labelHeight = min(
                label.font.lineHeight * 2,
                label.sizeThatFits(
                    CGSize(width: bounds.width - 16, height: .greatestFiniteMagnitude)
                ).height
            )
            let contentHeight = 25 + 8 + labelHeight
            let contentY = (bounds.height - contentHeight) / 2
            badge.frame = CGRect(x: 8, y: contentY, width: 25, height: 25)
            label.frame = CGRect(
                x: 8,
                y: contentY + 33,
                width: bounds.width - 16,
                height: labelHeight
            )
        } else {
            badge.frame = CGRect(
                x: 7,
                y: (bounds.height - 19) / 2,
                width: 19,
                height: 19
            )
            label.frame = CGRect(
                x: 32,
                y: 7,
                width: bounds.width - 39,
                height: bounds.height - 14
            )
        }
    }
}

@MainActor
final class UIKitPeriodNewGroundTileView: UIKitRoundedSummaryTileView {
    private let symbolView = UIImageView()
    private let label = UILabel()
    private var symbolIsCompact: Bool?

    override init(frame: CGRect) {
        super.init(frame: frame)
        symbolView.tintColor = .systemMint
        symbolView.contentMode = .scaleAspectFit
        label.font = summaryFont(.subheadline, weight: .semibold)
        label.numberOfLines = 2
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        [symbolView, label].forEach(addSubview)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(count: Int) {
        label.text = String(localized: "\(count) new places")
        accessibilityLabel = label.text
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let compact = bounds.height < 76
        let padding: CGFloat = compact ? 7 : 8
        let pointSize: CGFloat = compact ? 12 : 23
        if symbolIsCompact != compact {
            symbolIsCompact = compact
            symbolView.image = UIImage(systemName: "sparkles")?
                .applyingSymbolConfiguration(UIImage.SymbolConfiguration(
                    pointSize: pointSize,
                    weight: compact ? .semibold : .regular
                ))
        }
        symbolView.frame = CGRect(
            x: padding,
            y: padding,
            width: pointSize,
            height: pointSize
        )
        let labelHeight = min(
            label.font.lineHeight * 2,
            label.sizeThatFits(
                CGSize(
                    width: bounds.width - padding * 2,
                    height: .greatestFiniteMagnitude
                )
            ).height
        )
        label.frame = CGRect(
            x: padding,
            y: bounds.height - padding - labelHeight,
            width: bounds.width - padding * 2,
            height: labelHeight
        )
    }
}

@MainActor
final class UIKitPeriodSleepTileView: UIKitRoundedSummaryTileView {
    private let symbolView = UIImageView()
    private let timeLabel = UILabel()
    private let rhythmLabel = UILabel()
    private var symbolIsCompact: Bool?

    override init(frame: CGRect) {
        super.init(frame: frame)
        symbolView.tintColor = .systemCyan
        symbolView.contentMode = .scaleAspectFit
        timeLabel.font = summaryFont(.subheadline, weight: .bold)
        timeLabel.numberOfLines = 1
        rhythmLabel.font = summaryFont(.caption2, weight: .medium)
        rhythmLabel.textColor = .secondaryLabel
        rhythmLabel.numberOfLines = 2
        rhythmLabel.adjustsFontSizeToFitWidth = true
        rhythmLabel.minimumScaleFactor = 0.7
        [symbolView, timeLabel, rhythmLabel].forEach(addSubview)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ sleep: PeriodSleepSummary) {
        timeLabel.text = String(
            format: "%d:%02d",
            sleep.averageWakeMinute / 60,
            sleep.averageWakeMinute % 60
        )
        rhythmLabel.text = String(localized: "±\(sleep.consistencyMinutes)m rhythm")
        accessibilityLabel = [timeLabel.text, rhythmLabel.text]
            .compactMap { $0 }.joined(separator: ", ")
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let compact = bounds.height < 76
        let padding: CGFloat = compact ? 7 : 8
        let pointSize: CGFloat = compact ? 12 : 23
        if symbolIsCompact != compact {
            symbolIsCompact = compact
            symbolView.image = UIImage(systemName: "sunrise.fill")?
                .applyingSymbolConfiguration(UIImage.SymbolConfiguration(
                    pointSize: pointSize,
                    weight: compact ? .semibold : .regular
                ))
        }
        symbolView.frame = CGRect(
            x: padding,
            y: padding,
            width: pointSize,
            height: pointSize
        )
        let availableWidth = bounds.width - padding * 2
        let rhythmHeight = min(
            rhythmLabel.font.lineHeight * 2,
            rhythmLabel.sizeThatFits(
                CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
            ).height
        )
        let timeHeight = timeLabel.font.lineHeight
        let labelsY = bounds.height - padding - rhythmHeight - timeHeight
        timeLabel.frame = CGRect(
            x: padding,
            y: labelsY,
            width: availableWidth,
            height: timeHeight
        )
        rhythmLabel.frame = CGRect(
            x: padding,
            y: labelsY + timeHeight,
            width: availableWidth,
            height: rhythmHeight
        )
    }
}

@MainActor
final class UIKitIconTextSummaryTileView: UIKitRoundedSummaryTileView {
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        symbolView.contentMode = .scaleAspectFit
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2
        subtitleLabel.adjustsFontSizeToFitWidth = true
        subtitleLabel.minimumScaleFactor = 0.7
        [symbolView, titleLabel, subtitleLabel].forEach(addSubview)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        symbol: String,
        symbolColor: UIColor,
        title: String,
        subtitle: String?
    ) {
        symbolView.image = UIImage(systemName: symbol)
        symbolView.tintColor = symbolColor
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: ", ")
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let compact = bounds.height < 76
        let padding: CGFloat = compact ? 7 : 8
        let iconSide: CGFloat = compact ? 14 : 20
        symbolView.frame = CGRect(x: padding, y: padding, width: iconSide, height: iconSide)
        let labelHeight: CGFloat = subtitleLabel.isHidden ? 36 : 40
        titleLabel.font = .systemFont(
            ofSize: compact ? 13 : 15,
            weight: subtitleLabel.isHidden ? .semibold : .bold
        )
        titleLabel.frame = CGRect(
            x: padding,
            y: bounds.height - padding - labelHeight,
            width: bounds.width - padding * 2,
            height: subtitleLabel.isHidden ? labelHeight : 22
        )
        subtitleLabel.frame = CGRect(
            x: padding,
            y: bounds.height - padding - 18,
            width: bounds.width - padding * 2,
            height: 18
        )
    }
}

@MainActor
final class UIKitActivitySummaryTileView: UIKitRoundedSummaryTileView {
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private var bars: [CALayer] = []
    private var values: [Int] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        symbolView.image = UIImage(
            systemName: "square.grid.3x3.fill",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 11,
                weight: .semibold
            )
        )
        symbolView.tintColor = .label
        titleLabel.font = summaryFont(.caption2, weight: .semibold)
        [symbolView, titleLabel].forEach(addSubview)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(values: [Int], title: String) {
        self.values = values
        titleLabel.text = title
        while bars.count < values.count {
            let bar = CALayer()
            disableImplicitAnimations(for: bar)
            layer.addSublayer(bar)
            bars.append(bar)
        }
        for (index, bar) in bars.enumerated() {
            bar.isHidden = index >= values.count
        }
        accessibilityLabel = title
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let labelHeight = titleLabel.font.lineHeight
        symbolView.frame = CGRect(x: 8, y: 8, width: 11, height: labelHeight)
        titleLabel.frame = CGRect(
            x: 25,
            y: 8,
            width: bounds.width - 33,
            height: labelHeight
        )
        guard !values.isEmpty else { return }
        let chartY = 8 + labelHeight + 5
        let chart = CGRect(
            x: 8,
            y: chartY,
            width: bounds.width - 16,
            height: bounds.height - chartY
        )
        let gap: CGFloat = 3
        let width = max(2, (chart.width - gap * CGFloat(max(0, values.count - 1)))
            / CGFloat(values.count))
        let peak = max(values.max() ?? 1, 1)
        for index in values.indices {
            let height = max(4, chart.height * CGFloat(values[index]) / CGFloat(peak))
            let bar = bars[index]
            bar.frame = CGRect(
                x: chart.minX + CGFloat(index) * (width + gap),
                y: chart.maxY - height,
                width: width,
                height: height
            )
            bar.cornerRadius = min(3, width / 2)
            bar.backgroundColor = tintColor.withAlphaComponent(
                values[index] == 0
                    ? 0.12
                    : 0.3 + 0.7 * CGFloat(values[index]) / CGFloat(peak)
            ).cgColor
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }

    func scaled(by factor: CGFloat) -> UIColor {
        guard factor != 1 else { return self }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return self
        }
        return UIColor(
            red: red * factor,
            green: green * factor,
            blue: blue * factor,
            alpha: alpha
        )
    }
}
