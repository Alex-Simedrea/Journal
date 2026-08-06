import CoreLocation
import Foundation

enum PeriodSummaryTileKind: String, Hashable, Identifiable, Sendable {
    case overview
    case people
    case movement
    case frequentRoute
    case place
    case cities
    case countries
    case photos
    case busiestDay
    case longestJourney
    case review
    case sleep
    case activity
    case newGround

    var id: String { rawValue }
}

struct PeriodSummaryTilePlacement: Equatable, Identifiable, Sendable {
    let tile: PeriodSummaryTileKind
    let frame: DaySummaryNormalizedFrame

    var id: PeriodSummaryTileKind { tile }
}

struct PeriodSummaryLayoutRecipe: Equatable, Sendable {
    static let referenceWidth = 408.0
    private static let columns = 4
    private static let gap = 8.0
    // Five fine-grained bands plus four gutters equal a two-column square:
    // 5 * 33.6 + 4 * 8 = 200.
    private static let rowHeight = 33.6
    private static let maximumExtraRows = 12
    private static let fullRow: UInt8 = 0b1111

    let referenceHeight: Double
    let placements: [PeriodSummaryTilePlacement]

    var isCompletelyFilled: Bool {
        guard referenceHeight > 0 else { return placements.isEmpty }
        let columnWidth = (Self.referenceWidth
            - Self.gap * Double(Self.columns - 1)) / Double(Self.columns)
        let rowCount = Int(
            ((referenceHeight + Self.gap) / (Self.rowHeight + Self.gap))
                .rounded()
        )
        return (0..<rowCount).allSatisfy { row in
            (0..<Self.columns).allSatisfy { column in
                let x = (Double(column) * (columnWidth + Self.gap)
                    + columnWidth / 2) / Self.referenceWidth
                let y = (Double(row) * (Self.rowHeight + Self.gap)
                    + Self.rowHeight / 2) / Self.referenceWidth
                return placements.filter { placement in
                    x >= placement.frame.x
                        && x <= placement.frame.x + placement.frame.width
                        && y >= placement.frame.y
                        && y <= placement.frame.y + placement.frame.height
                }.count == 1
            }
        }
    }

    static func make(for summary: PeriodSummary) -> Self {
        let specs = tileSpecs(for: summary)
        guard !specs.isEmpty else {
            return Self(referenceHeight: 0, placements: [])
        }

        let minimumArea = specs.reduce(0) { result, spec in
            result + (spec.options.map(\.area).min() ?? 0)
        }
        let minimumRows = max(
            specs.flatMap(\.options).map(\.rows).max() ?? 1,
            Int(ceil(Double(minimumArea) / Double(columns)))
        )

        for rowCount in minimumRows...(minimumRows + maximumExtraRows) {
            guard canFillArea(specs: specs, area: rowCount * columns) else {
                continue
            }
            var solver = ExactFillSolver(specs: specs, rowCount: rowCount)
            if let packed = solver.solve() {
                return recipe(from: packed, rowCount: rowCount)
            }
        }

        // Every normal period has enough flexible cards for exact packing.
        // Keep a deterministic compact fallback for exceptionally sparse data.
        let fallback = deterministicFallback(specs)
        return recipe(from: fallback.placements, rowCount: fallback.rowCount)
    }

    private struct TileSize: Equatable {
        let columns: Int
        let rows: Int

        init(_ columns: Int, _ rows: Int) {
            self.columns = columns
            self.rows = rows
        }

        var area: Int { columns * rows }
    }

    private struct TileSpec {
        let tile: PeriodSummaryTileKind
        let options: [TileSize]
    }

    private struct PackedTile {
        let tile: PeriodSummaryTileKind
        let size: TileSize
        let row: Int
        let column: Int
    }

    private struct SearchKey: Hashable {
        let occupied: [UInt8]
        let remaining: UInt32
    }

    private struct ExactFillSolver {
        let specs: [TileSpec]
        let rowCount: Int
        private var failedStates: Set<SearchKey> = []
        private var visitedStateCount = 0
        private let stateBudget = 60_000

        init(specs: [TileSpec], rowCount: Int) {
            self.specs = specs
            self.rowCount = rowCount
        }

        mutating func solve() -> [PackedTile]? {
            guard specs.count < UInt32.bitWidth else { return nil }
            var occupied = Array(repeating: UInt8(0), count: rowCount)
            var placements: [PackedTile] = []
            var remaining = specs.indices.reduce(UInt32(0)) {
                $0 | (UInt32(1) << UInt32($1))
            }
            if let overviewIndex = specs.firstIndex(where: {
                $0.tile == .overview
            }), let size = specs[overviewIndex].options.first,
               size.rows <= rowCount {
                occupy(
                    size,
                    at: (row: 0, column: 0),
                    rows: &occupied,
                    value: true
                )
                placements.append(PackedTile(
                    tile: .overview,
                    size: size,
                    row: 0,
                    column: 0
                ))
                remaining &= ~(UInt32(1) << UInt32(overviewIndex))
            }
            guard fill(
                occupied: &occupied,
                remaining: remaining,
                placements: &placements
            ) else { return nil }
            return placements
        }

        private mutating func fill(
            occupied: inout [UInt8],
            remaining: UInt32,
            placements: inout [PackedTile]
        ) -> Bool {
            if remaining == 0 {
                return occupied.allSatisfy { $0 == fullRow }
            }
            visitedStateCount += 1
            guard visitedStateCount <= stateBudget else { return false }

            let key = SearchKey(occupied: occupied, remaining: remaining)
            guard !failedStates.contains(key),
                  remainingAreaCanFill(occupied: occupied, remaining: remaining),
                  let position = firstEmptyCell(in: occupied) else {
                failedStates.insert(key)
                return false
            }

            for index in specs.indices where contains(index, in: remaining) {
                let spec = specs[index]
                for size in spec.options where fits(
                    size,
                    at: position,
                    occupied: occupied
                ) {
                    occupy(size, at: position, rows: &occupied, value: true)
                    placements.append(PackedTile(
                        tile: spec.tile,
                        size: size,
                        row: position.row,
                        column: position.column
                    ))
                    let nextRemaining = remaining
                        & ~(UInt32(1) << UInt32(index))
                    if fill(
                        occupied: &occupied,
                        remaining: nextRemaining,
                        placements: &placements
                    ) {
                        return true
                    }
                    placements.removeLast()
                    occupy(size, at: position, rows: &occupied, value: false)
                }
            }

            failedStates.insert(key)
            return false
        }

        private func remainingAreaCanFill(
            occupied: [UInt8],
            remaining: UInt32
        ) -> Bool {
            let emptyCount = occupied.reduce(0) {
                $0 + columns - $1.nonzeroBitCount
            }
            var minimum = 0
            var maximum = 0
            for index in specs.indices where contains(index, in: remaining) {
                let areas = specs[index].options.map(\.area)
                minimum += areas.min() ?? 0
                maximum += areas.max() ?? 0
            }
            return minimum <= emptyCount && emptyCount <= maximum
        }

        private func firstEmptyCell(
            in occupied: [UInt8]
        ) -> (row: Int, column: Int)? {
            for row in occupied.indices where occupied[row] != fullRow {
                for column in 0..<columns
                where occupied[row] & (UInt8(1) << UInt8(column)) == 0 {
                    return (row, column)
                }
            }
            return nil
        }

        private func fits(
            _ size: TileSize,
            at position: (row: Int, column: Int),
            occupied: [UInt8]
        ) -> Bool {
            guard position.column + size.columns <= columns,
                  position.row + size.rows <= rowCount else { return false }
            let mask = ((UInt8(1) << UInt8(size.columns)) - 1)
                << UInt8(position.column)
            return (position.row..<(position.row + size.rows)).allSatisfy {
                occupied[$0] & mask == 0
            }
        }

        private func occupy(
            _ size: TileSize,
            at position: (row: Int, column: Int),
            rows: inout [UInt8],
            value: Bool
        ) {
            let mask = ((UInt8(1) << UInt8(size.columns)) - 1)
                << UInt8(position.column)
            for row in position.row..<(position.row + size.rows) {
                if value {
                    rows[row] |= mask
                } else {
                    rows[row] &= ~mask
                }
            }
        }

        private func contains(_ index: Int, in mask: UInt32) -> Bool {
            mask & (UInt32(1) << UInt32(index)) != 0
        }
    }

    private static func recipe(
        from packed: [PackedTile],
        rowCount: Int
    ) -> Self {
        let columnWidth = (referenceWidth - gap * Double(columns - 1))
            / Double(columns)
        let placements = packed.map { placement in
            PeriodSummaryTilePlacement(
                tile: placement.tile,
                frame: DaySummaryNormalizedFrame(
                    x: Double(placement.column) * (columnWidth + gap)
                        / referenceWidth,
                    y: Double(placement.row) * (rowHeight + gap)
                        / referenceWidth,
                    width: (columnWidth * Double(placement.size.columns)
                        + gap * Double(placement.size.columns - 1))
                        / referenceWidth,
                    height: (rowHeight * Double(placement.size.rows)
                        + gap * Double(placement.size.rows - 1))
                        / referenceWidth
                )
            )
        }
        let height = rowHeight * Double(rowCount)
            + gap * Double(max(0, rowCount - 1))
        return Self(referenceHeight: height, placements: placements)
    }

    private static func deterministicFallback(
        _ specs: [TileSpec]
    ) -> (placements: [PackedTile], rowCount: Int) {
        var occupied = Array(repeating: UInt8(0), count: 96)
        var result: [PackedTile] = []
        var maximumRow = 0
        for spec in specs {
            let size = spec.options[0]
            outer: for row in occupied.indices {
                for column in 0...(columns - size.columns) {
                    let mask = ((UInt8(1) << UInt8(size.columns)) - 1)
                        << UInt8(column)
                    guard row + size.rows <= occupied.count,
                          (row..<(row + size.rows)).allSatisfy({
                              occupied[$0] & mask == 0
                          }) else { continue }
                    for checkedRow in row..<(row + size.rows) {
                        occupied[checkedRow] |= mask
                    }
                    maximumRow = max(maximumRow, row + size.rows)
                    result.append(PackedTile(
                        tile: spec.tile,
                        size: size,
                        row: row,
                        column: column
                    ))
                    break outer
                }
            }
        }
        return (result, maximumRow)
    }

    private static func canFillArea(
        specs: [TileSpec],
        area: Int
    ) -> Bool {
        var possible: Set<Int> = [0]
        for spec in specs {
            possible = Set(possible.flatMap { subtotal in
                spec.options.map { subtotal + $0.area }.filter { $0 <= area }
            })
            guard !possible.isEmpty else { return false }
        }
        return possible.contains(area)
    }

    private static func tileSpecs(for summary: PeriodSummary) -> [TileSpec] {
        var result: [TileSpec] = []
        if summary.overviewData.hasContent {
            result.append(.init(tile: .overview, options: [
                .init(2, 5),
            ]))
        }
        if !summary.people.isEmpty {
            result.append(.init(tile: .people, options: [
                .init(2, 2), .init(3, 2), .init(4, 2),
            ]))
        }
        if summary.movement != nil {
            result.append(.init(tile: .movement, options: [
                .init(2, 2), .init(3, 2), .init(2, 3),
            ]))
        }
        if !summary.photos.isEmpty {
            let options = summary.photos.count == 1
                ? [TileSize(1, 3), TileSize(2, 5)]
                : [TileSize(2, 5)]
            result.append(.init(tile: .photos, options: options))
        }
        if let route = summary.frequentRoute {
            result.append(.init(
                tile: .frequentRoute,
                options: routeOptions(for: route.mapData)
            ))
        }
        if let journey = summary.longestJourney {
            result.append(.init(
                tile: .longestJourney,
                options: routeOptions(for: journey.mapData)
            ))
        }
        if summary.mostVisitedPlace != nil {
            result.append(.init(tile: .place, options: [
                .init(1, 3), .init(2, 3), .init(1, 4),
            ]))
        }
        if !summary.cities.isEmpty {
            result.append(.init(tile: .cities, options: compactOptions))
        }
        let showsCountries = switch summary.key {
        case .month: summary.countries.count > 1
        case .year: !summary.countries.isEmpty
        }
        if showsCountries {
            result.append(.init(tile: .countries, options: compactOptions))
        }
        result.append(.init(tile: .activity, options: [
            .init(2, 3), .init(3, 3), .init(2, 4),
        ]))
        if summary.sleep != nil {
            result.append(.init(tile: .sleep, options: compactOptions))
        }
        if summary.busiestDay != nil {
            result.append(.init(tile: .busiestDay, options: compactOptions))
        }
        if summary.newGroundCount > 0 {
            result.append(.init(tile: .newGround, options: compactOptions))
        }
        if summary.reviewCount > 0 {
            result.append(.init(tile: .review, options: compactOptions))
        }
        return result
    }

    private static let compactOptions: [TileSize] = [
        .init(1, 2), .init(2, 2), .init(1, 3),
    ]

    private static func routeOptions(
        for data: TimelineOverviewData
    ) -> [TileSize] {
        switch routeOrientation(data) {
        case .horizontal:
            [.init(2, 3), .init(3, 3), .init(2, 4)]
        case .vertical:
            [.init(1, 5), .init(2, 5), .init(1, 6)]
        case .balanced:
            [.init(2, 3), .init(2, 4), .init(2, 5)]
        }
    }

    private enum RouteOrientation {
        case horizontal
        case vertical
        case balanced
    }

    private static func routeOrientation(
        _ data: TimelineOverviewData
    ) -> RouteOrientation {
        let coordinates = data.paths.flatMap(\.coordinates)
            + data.markers.map(\.coordinate)
        guard coordinates.count > 1 else { return .balanced }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minimumLatitude = latitudes.min(),
              let maximumLatitude = latitudes.max(),
              let minimumLongitude = longitudes.min(),
              let maximumLongitude = longitudes.max() else { return .balanced }
        let meanLatitude = (minimumLatitude + maximumLatitude) / 2
        let vertical = maximumLatitude - minimumLatitude
        let horizontal = (maximumLongitude - minimumLongitude)
            * max(0.2, cos(meanLatitude * .pi / 180))
        if horizontal > vertical * 1.45 { return .horizontal }
        if vertical > horizontal * 1.45 { return .vertical }
        return .balanced
    }
}
