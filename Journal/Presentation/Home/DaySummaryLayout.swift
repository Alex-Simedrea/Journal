import Foundation

enum DaySummaryTileKind: String, Hashable, Identifiable, Sendable {
    case overview
    case weather
    case people
    case photos
    case movement
    case wakeUp
    case featuredPlace
    case review

    var id: String { rawValue }
}

struct DaySummaryNormalizedFrame: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct DaySummaryTilePlacement: Equatable, Identifiable, Sendable {
    let tile: DaySummaryTileKind
    let frame: DaySummaryNormalizedFrame

    var id: DaySummaryTileKind { tile }
}

struct DaySummaryLayoutRecipe: Equatable, Sendable {
    enum Variant: Equatable, Sendable {
        case review
        case overviewThreeColumn
        case overviewTwoColumn
        case overviewOnly
        case twoColumn
        case singleColumn
    }

    static let referenceWidth = 372.0
    static let movementExpansionThreshold = 55.0
    static let expandedMovementMinimumHeight = 75.0
    private static let gap = 8.0

    let variant: Variant
    let referenceHeight: Double
    let placements: [DaySummaryTilePlacement]

    static func make(for summary: DaySummary) -> DaySummaryLayoutRecipe {
        if summary.showsNeedsReviewPlaceholder {
            return makeRecipe(
                variant: .review,
                columns: [(0, 372, [.review])],
                summary: summary
            )
        }

        let balanced = balancedColumns(for: summary)

        if summary.showsOverviewMap {
            if !balanced.primary.isEmpty, !balanced.trailing.isEmpty {
                return makeRecipe(
                    variant: .overviewThreeColumn,
                    columns: [
                        (0, 151, [.overview]),
                        (159, 107, balanced.primary),
                        (274, 98, balanced.trailing),
                    ],
                    summary: summary
                )
            }

            let secondary = balanced.primary + balanced.trailing
            if !secondary.isEmpty {
                return makeRecipe(
                    variant: .overviewTwoColumn,
                    columns: [
                        (0, 209, [.overview]),
                        (217, 155, secondary),
                    ],
                    summary: summary
                )
            }

            return DaySummaryLayoutRecipe(
                variant: .overviewOnly,
                referenceHeight: 90,
                placements: [placement(.overview, 0, 0, 372, 90)]
            )
        }

        if !balanced.primary.isEmpty, !balanced.trailing.isEmpty {
            return makeRecipe(
                variant: .twoColumn,
                columns: [
                    (0, 182, balanced.primary),
                    (190, 182, balanced.trailing),
                ],
                summary: summary
            )
        }

        let remaining = balanced.primary + balanced.trailing
        return makeRecipe(
            variant: .singleColumn,
            columns: [(0, 372, remaining)],
            summary: summary
        )
    }

    static func showsWakeUp(in summary: DaySummary) -> Bool {
        summary.wakeUp != nil
    }

    private typealias Column = (
        x: Double,
        width: Double,
        tiles: [DaySummaryTileKind]
    )

    private struct BalancedColumns {
        let primary: [DaySummaryTileKind]
        let trailing: [DaySummaryTileKind]
        let score: Double
    }

    private static func balancedColumns(
        for summary: DaySummary
    ) -> BalancedColumns {
        let hasWeather = summary.weatherRequest != nil
        let hasPeople = !summary.people.isEmpty
        let hasMovement = summary.movement != nil
        let hasPhotos = !summary.photos.isEmpty
        let hasWakeUp = showsWakeUp(in: summary)
        let hasFeaturedPlace = summary.featuredPlace != nil

        let movementOptions = hasMovement ? [false, true] : [false]
        let wakeOptions = hasWakeUp ? [false, true] : [false]
        var candidates: [BalancedColumns] = []

        for movementInTrailing in movementOptions {
            for wakeInPrimary in wakeOptions {
                var primary: [DaySummaryTileKind] = []
                var trailing: [DaySummaryTileKind] = []

                if hasWeather { primary.append(.weather) }
                if hasPeople { primary.append(.people) }
                if hasMovement, !movementInTrailing {
                    primary.append(.movement)
                }
                if hasWakeUp, wakeInPrimary {
                    primary.append(.wakeUp)
                }

                if hasMovement, movementInTrailing {
                    trailing.append(.movement)
                }
                if hasPhotos { trailing.append(.photos) }
                if hasWakeUp, !wakeInPrimary {
                    trailing.append(.wakeUp)
                }
                if hasFeaturedPlace { trailing.append(.featuredPlace) }

                let primaryHeight = minimumColumnHeight(
                    primary,
                    summary: summary
                )
                let trailingHeight = minimumColumnHeight(
                    trailing,
                    summary: summary
                )
                let rowHeight = resolvedRowHeight(
                    for: [primary, trailing],
                    summary: summary
                )
                let expansionCost = expansionCost(
                    primary,
                    from: primaryHeight,
                    to: rowHeight,
                    summary: summary
                ) + expansionCost(
                    trailing,
                    from: trailingHeight,
                    to: rowHeight,
                    summary: summary
                )
                let relocationCost = (movementInTrailing ? 4.0 : 0)
                    + (wakeInPrimary ? 8.0 : 0)
                candidates.append(
                    BalancedColumns(
                        primary: primary,
                        trailing: trailing,
                        score: rowHeight * 5
                            + expansionCost
                            + relocationCost
                    )
                )
            }
        }

        return candidates.min { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return minimumColumnHeight(lhs.primary, summary: summary)
                < minimumColumnHeight(rhs.primary, summary: summary)
        } ?? BalancedColumns(primary: [], trailing: [], score: 0)
    }

    private static func makeRecipe(
        variant: Variant,
        columns: [Column],
        summary: DaySummary
    ) -> DaySummaryLayoutRecipe {
        let contentColumns = columns.filter { $0.tiles != [.overview] }
        let contentHeight = resolvedRowHeight(
            for: contentColumns.map(\.tiles),
            summary: summary
        )
        let height = max(contentHeight, columns.contains { $0.tiles == [.overview] }
            ? 45
            : 0)

        let placements = columns.flatMap { column in
            if column.tiles == [.overview] {
                return [placement(.overview, column.x, 0, column.width, height)]
            }
            return verticalFrames(
                for: column.tiles,
                x: column.x,
                width: column.width,
                targetHeight: height,
                summary: summary
            )
        }
        return DaySummaryLayoutRecipe(
            variant: variant,
            referenceHeight: max(height, 45),
            placements: placements
        )
    }

    private static func minimumColumnHeight(
        _ tiles: [DaySummaryTileKind],
        summary: DaySummary
    ) -> Double {
        guard !tiles.isEmpty else { return 0 }
        return tiles.reduce(0) {
            $0 + minimumHeight(for: $1, summary: summary)
        } + Double(tiles.count - 1) * gap
    }

    private static func resolvedRowHeight(
        for columns: [[DaySummaryTileKind]],
        summary: DaySummary
    ) -> Double {
        var height = columns.map {
            minimumColumnHeight($0, summary: summary)
        }.max() ?? 0

        while true {
            let resolvedHeight = columns.map {
                minimumColumnHeight(
                    $0,
                    whenExpandedTo: height,
                    summary: summary
                )
            }.max() ?? height
            guard resolvedHeight > height else { return height }
            height = resolvedHeight
        }
    }

    private static func minimumColumnHeight(
        _ tiles: [DaySummaryTileKind],
        whenExpandedTo targetHeight: Double,
        summary: DaySummary
    ) -> Double {
        let baseHeight = minimumColumnHeight(tiles, summary: summary)
        guard targetHeight > baseHeight,
              let absorber = tiles.indices.min(by: {
                  expansionResistance(for: tiles[$0], summary: summary)
                      < expansionResistance(for: tiles[$1], summary: summary)
              }),
              tiles[absorber] == .movement else {
            return baseHeight
        }

        let movementHeight = minimumHeight(for: .movement, summary: summary)
        let expandedHeight = movementHeight + targetHeight - baseHeight
        guard expandedHeight >= movementExpansionThreshold else {
            return baseHeight
        }
        return baseHeight
            + max(0, expandedMovementMinimumHeight - movementHeight)
    }

    private static func minimumHeight(
        for tile: DaySummaryTileKind,
        summary: DaySummary
    ) -> Double {
        switch tile {
        case .overview: 45
        case .weather: isContentHeavy(summary) ? 90 : 45
        case .people: 50
        case .photos: summary.photos.count >= 3 ? 96 : 45
        case .movement:
            requiresExpandedMovement(summary)
                ? expandedMovementMinimumHeight
                : 37
        case .wakeUp: 38
        case .featuredPlace: 71
        case .review: 72
        }
    }

    private static func expansionResistance(
        for tile: DaySummaryTileKind,
        summary: DaySummary
    ) -> Double {
        switch tile {
        case .movement: 1
        case .photos: 2
        case .featuredPlace:
            isContentHeavy(summary) && requiresExpandedMovement(summary)
                ? 0.5
                : 4
        case .people: 10
        case .weather: 12
        case .wakeUp: 20
        case .overview, .review: 0
        }
    }

    private static func expansionCost(
        _ tiles: [DaySummaryTileKind],
        from minimumHeight: Double,
        to targetHeight: Double,
        summary: DaySummary
    ) -> Double {
        guard !tiles.isEmpty, targetHeight > minimumHeight else { return 0 }
        let resistance = tiles.map {
            expansionResistance(for: $0, summary: summary)
        }.min() ?? 0
        return (targetHeight - minimumHeight) * resistance
    }

    private static func verticalFrames(
        for tiles: [DaySummaryTileKind],
        x: Double,
        width: Double,
        targetHeight: Double,
        summary: DaySummary
    ) -> [DaySummaryTilePlacement] {
        guard !tiles.isEmpty else { return [] }
        var heights = tiles.map { minimumHeight(for: $0, summary: summary) }
        let minimumHeight = heights.reduce(0, +)
            + Double(tiles.count - 1) * gap
        let deficit = max(0, targetHeight - minimumHeight)
        if deficit > 0,
           let absorber = tiles.indices.min(by: {
               expansionResistance(for: tiles[$0], summary: summary)
                   < expansionResistance(for: tiles[$1], summary: summary)
           }) {
            heights[absorber] += deficit
        }

        var y = 0.0
        return zip(tiles, heights).map { tile, height in
            defer { y += height + gap }
            return placement(tile, x, y, width, height)
        }
    }

    private static func placement(
        _ tile: DaySummaryTileKind,
        _ x: Double,
        _ y: Double,
        _ width: Double,
        _ height: Double
    ) -> DaySummaryTilePlacement {
        DaySummaryTilePlacement(
            tile: tile,
            frame: DaySummaryNormalizedFrame(
                x: x / referenceWidth,
                y: y / referenceWidth,
                width: width / referenceWidth,
                height: height / referenceWidth
            )
        )
    }

    private static func requiresExpandedMovement(
        _ summary: DaySummary
    ) -> Bool {
        (summary.movement?.icons.count ?? 0) >= 3
    }

    private static func isContentHeavy(_ summary: DaySummary) -> Bool {
        let entryCount = Set(summary.occurrences.map(\.id.entryID)).count
        let hasRichContentMix = summary.photos.count >= 3
            && !summary.people.isEmpty
            && requiresExpandedMovement(summary)
            && summary.featuredPlace != nil
        return entryCount >= 6 || hasRichContentMix
    }
}
