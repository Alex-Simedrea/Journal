import SwiftUI
import UIKit

/// Semantic descriptions are collected only when changing scale, never while scrolling.
struct HomeFeedZoomTile {
    enum Family: String {
        case map, photos, people, movement, sleep, activity, cities, countries, review, newGround
    }

    let id: String
    let owner: String
    let role: String
    let family: Family
    let days: Set<TimelineDayKey>
    let contentIDs: Set<String>
    let frame: CGRect
    weak var view: UIView? = nil

    func fullyVisible(in viewport: CGRect) -> HomeFeedZoomTile? {
        guard frame.width > 20, frame.height > 20,
              viewport.contains(frame) else { return nil }
        return self
    }
}

struct HomeFeedZoomMatch {
    let source: Int
    let target: Int
}

enum HomeFeedZoomMatcher {
    static let tileBudget = 5

    /// One-to-one matching. Card coverage wins before proximity, so multiple
    /// period maps fan into different visible days instead of crowding the top day.
    static func matches(
        from source: [HomeFeedZoomTile],
        to target: [HomeFeedZoomTile],
        limit: Int = tileBudget
    ) -> [HomeFeedZoomMatch] {
        var result: [HomeFeedZoomMatch] = []
        var usedSource: Set<Int> = []
        var usedTarget: Set<Int> = []
        var sourceOwners: Set<String> = []
        var targetOwners: Set<String> = []
        var families: Set<HomeFeedZoomTile.Family> = []
        while result.count < limit {
            var best: (HomeFeedZoomMatch, Double)?
            for (i, lhs) in source.enumerated() where !usedSource.contains(i) {
                for (j, rhs) in target.enumerated() where !usedTarget.contains(j) {
                    guard lhs.family == rhs.family,
                          !lhs.days.isDisjoint(with: rhs.days) else { continue }
                    let sharedContent = !lhs.contentIDs.isDisjoint(with: rhs.contentIDs)
                    // Photos and people should carry actual shared identity.
                    if (lhs.family == .photos || lhs.family == .people), !sharedContent {
                        continue
                    }
                    let distance = hypot(lhs.frame.midX - rhs.frame.midX,
                                         lhs.frame.midY - rhs.frame.midY)
                    let score = (sourceOwners.contains(lhs.owner) ? 0.0 : 1_000)
                        + (targetOwners.contains(rhs.owner) ? 0.0 : 1_000)
                        + (families.contains(lhs.family) ? 0.0 : 300)
                        + (sharedContent ? 200.0 : 0)
                        + (lhs.role == rhs.role ? 80.0 : 0)
                        - min(Double(distance), 2_000) * 0.05
                    if best == nil || score > best!.1 {
                        best = (HomeFeedZoomMatch(source: i, target: j), score)
                    }
                }
            }
            guard let match = best?.0 else { break }
            result.append(match)
            usedSource.insert(match.source)
            usedTarget.insert(match.target)
            sourceOwners.insert(source[match.source].owner)
            targetOwners.insert(target[match.target].owner)
            families.insert(source[match.source].family)
        }
        return result
    }
}

/// Apple's spring solver can drive UIKit snapshots without a SwiftUI view tree.
/// Changing `target` keeps both position and velocity, including on a third destination.
struct HomeFeedZoomSpring {
    var value: Double
    var velocity = 0.0
    var target: Double
    private static let spring = Spring(duration: 0.38, bounce: 0)

    init(_ value: Double) {
        self.value = value
        target = value
    }

    mutating func advance(by interval: TimeInterval) {
        Self.spring.update(value: &value, velocity: &velocity,
                           target: target, deltaTime: interval)
    }

    var isSettled: Bool { abs(value - target) < 0.001 && abs(velocity) < 0.01 }
}

extension JournalSummaryScale {
    var zoomDepth: Double {
        switch self {
        case .days: 0
        case .months: 1
        case .years: 2
        }
    }
}

extension UIKitDaySummaryCanvasView {
    func zoomTiles(summary: DaySummary, in viewport: UIView) -> [HomeFeedZoomTile] {
        let owner = "day-\(summary.day.id)"
        return transitionTileViews.compactMap { kind, view in
            let family: HomeFeedZoomTile.Family
            var ids: Set<String> = []
            switch kind {
            case .overview: family = .map
            case .featuredPlace:
                family = .map
                ids = Set([summary.featuredPlace?.location.id].compactMap { $0 })
            case .photos:
                family = .photos
                ids = Set(summary.photos.map(\.id))
            case .people:
                family = .people
                ids = Set(summary.people.map { $0.id.uuidString })
            case .movement: family = .movement
            case .wakeUp: family = .sleep
            case .review: family = .review
            case .weather: return nil
            }
            return HomeFeedZoomTile(id: owner + "/" + kind.rawValue, owner: owner,
                role: kind.rawValue, family: family, days: [summary.day], contentIDs: ids,
                frame: view.convert(view.bounds, to: viewport), view: view)
        }
    }
}

extension UIKitPeriodSummaryCanvasView {
    func zoomTiles(summary: PeriodSummary, in viewport: UIView) -> [HomeFeedZoomTile] {
        let owner = summary.key.id
        return transitionTileViews.compactMap { kind, view in
            let family: HomeFeedZoomTile.Family
            var ids: Set<String> = []
            var days = Set(summary.days.map(\.day))
            switch kind {
            case .overview, .frequentRoute: family = .map
            case .longestJourney:
                family = .map
                if let day = summary.longestJourney?.day { days = [day] }
            case .place:
                family = .map
                ids = Set([summary.mostVisitedPlace?.location.id].compactMap { $0 })
            case .photos:
                family = .photos
                ids = Set(summary.photos.map(\.id))
            case .people:
                family = .people
                ids = Set(summary.people.map { $0.id.uuidString })
            case .movement: family = .movement
            case .sleep: family = .sleep
            case .activity: family = .activity
            case .cities: family = .cities
            case .countries: family = .countries
            case .review: family = .review
            case .newGround: family = .newGround
            case .busiestDay: return nil
            }
            return HomeFeedZoomTile(id: owner + "/" + kind.rawValue, owner: owner,
                role: kind.rawValue, family: family, days: days, contentIDs: ids,
                frame: view.convert(view.bounds, to: viewport), view: view)
        }
    }
}
