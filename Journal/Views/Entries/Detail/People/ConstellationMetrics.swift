import SwiftUI

nonisolated struct EntryDetailPeopleBubblePlacement {
    let center: CGPoint
    let diameter: CGFloat
}

nonisolated enum EntryDetailPeopleConstellationMetrics {
    static let fallbackWidth: CGFloat = 138
    static let height: CGFloat = 56
    static let gap: CGFloat = 2

    static func placements(count: Int) -> [EntryDetailPeopleBubblePlacement] {
        makePlacements(count: min(max(count, 0), 12))
    }

    static func scale(
        for availableWidth: CGFloat,
        placements: [EntryDetailPeopleBubblePlacement]
    ) -> CGFloat {
        guard !placements.isEmpty else { return 1 }
        let width = boundingRect(for: placements).width
        guard width > 0 else { return 1 }
        return min(1, max(0, (availableWidth - 4) / width))
    }

    static func boundingRect(
        for placements: [EntryDetailPeopleBubblePlacement]
    ) -> CGRect {
        placements.reduce(.null) { bounds, placement in
            bounds.union(
                CGRect(
                    x: placement.center.x - placement.diameter / 2,
                    y: placement.center.y - placement.diameter / 2,
                    width: placement.diameter,
                    height: placement.diameter
                )
            )
        }
    }

    private static func makePlacements(
        count: Int
    ) -> [EntryDetailPeopleBubblePlacement] {
        switch count {
        case 0:
            return []
        case 1:
            return [bubble(0, 0, 54)]
        case 2:
            return centered([
                bubble(-17, -5, 34), bubble(18, 5, 32),
            ])
        case 3:
            return threeBubbleCluster
        case 4:
            return fourBubbleCluster
        case 5:
            return prominentUpperThree(lowerDiameters: [23, 23])
        case 6:
            return prominentUpperThree(
                upperDiameters: [26, 29, 26],
                lowerDiameters: [18, 22, 18],
                archAngle: .pi / 45
            )
        case 7:
            return prominentUpperThree(
                upperDiameters: [29, 32, 29],
                lowerDiameters: [17, 22, 22, 17],
                archAngle: .pi / 45
            )
        case 8:
            return prominentUpperThree(
                upperDiameters: [27, 30, 27],
                lowerDiameters: [16, 21, 24, 21, 16],
                archAngle: .pi / 45
            )
        case 9:
            return stackedRows(
                upperDiameters: [20, 28, 28, 20],
                lowerDiameters: [15, 22, 25, 22, 15]
            )
        case 10:
            return stackedRows(
                upperDiameters: [24, 30, 30, 24],
                lowerDiameters: [16, 21, 24, 24, 21, 16]
            )
        case 11:
            return stackedRows(
                upperDiameters: [17, 23, 27, 23, 17],
                lowerDiameters: [16, 21, 24, 24, 21, 16]
            )
        default:
            return stackedRows(
                upperDiameters: [19, 24, 28, 24, 19],
                lowerDiameters: [13, 17, 21, 23, 21, 17, 13]
            )
        }
    }

    private static var threeBubbleCluster: [EntryDetailPeopleBubblePlacement] {
        let firstDiameter: CGFloat = 32
        let secondDiameter: CGFloat = 28
        let lowerDiameter: CGFloat = 24
        let upperDistance = (firstDiameter + secondDiameter) / 2 + gap
        let firstToLower = (firstDiameter + lowerDiameter) / 2 + gap
        let secondToLower = (secondDiameter + lowerDiameter) / 2 + gap
        let lowerXFromFirst =
            (firstToLower * firstToLower
                - secondToLower * secondToLower
                + upperDistance * upperDistance)
            / (2 * upperDistance)
        let lowerY = sqrt(
            firstToLower * firstToLower
                - lowerXFromFirst * lowerXFromFirst
        )

        return centered([
            bubble(-upperDistance / 2, 0, firstDiameter),
            bubble(upperDistance / 2, 0, secondDiameter),
            bubble(
                -upperDistance / 2 + lowerXFromFirst,
                lowerY,
                lowerDiameter
            ),
        ])
    }

    private static var fourBubbleCluster: [EntryDetailPeopleBubblePlacement] {
        let mainDiameter: CGFloat = 32
        let sideDiameter: CGFloat = 31
        let lowerDiameter: CGFloat = 22
        let verticalDistance = (mainDiameter + lowerDiameter) / 2 + gap
        let mainToSide = (mainDiameter + sideDiameter) / 2 + gap
        let lowerToSide = (lowerDiameter + sideDiameter) / 2 + gap
        let sideYFromMain =
            (mainToSide * mainToSide
                - lowerToSide * lowerToSide
                + verticalDistance * verticalDistance)
            / (2 * verticalDistance)
        let sideX = sqrt(
            mainToSide * mainToSide - sideYFromMain * sideYFromMain
        )
        let mainY = -verticalDistance / 2
        let lowerY = verticalDistance / 2
        let sideY = mainY + sideYFromMain

        return centered([
            bubble(0, mainY, mainDiameter),
            bubble(-sideX, sideY, sideDiameter),
            bubble(0, lowerY, lowerDiameter),
            bubble(sideX, sideY, sideDiameter),
        ])
    }

    private static func prominentUpperThree(
        upperDiameters: [CGFloat] = [27, 30, 27],
        lowerDiameters: [CGFloat],
        archAngle: CGFloat = .pi / 30
    ) -> [EntryDetailPeopleBubblePlacement] {
        let placements = stackedRows(
            upperDiameters: upperDiameters,
            lowerDiameters: lowerDiameters,
            archAngle: archAngle
        )
        return [placements[1], placements[0], placements[2]]
            + placements.dropFirst(3)
    }

    private static func stackedRows(
        upperDiameters: [CGFloat],
        lowerDiameters: [CGFloat],
        archAngle: CGFloat = .pi / 30
    ) -> [EntryDetailPeopleBubblePlacement] {
        let upper = tangentRow(
            diameters: upperDiameters,
            archAngle: archAngle
        )
        let lower = tangentRow(
            diameters: lowerDiameters,
            archAngle: -archAngle
        )
        let separation = rowSeparation(upper: upper, lower: lower)

        return centered(
            upper.map { placement in
                placement.offsetBy(y: -separation / 2)
            }
                + lower.map { placement in
                    placement.offsetBy(y: separation / 2)
                }
        )
    }

    private static func tangentRow(
        diameters: [CGFloat],
        archAngle: CGFloat
    ) -> [EntryDetailPeopleBubblePlacement] {
        guard let firstDiameter = diameters.first else { return [] }
        guard diameters.count > 1 else {
            return [bubble(0, 0, firstDiameter)]
        }

        let segmentCount = diameters.count - 1
        var placements = [bubble(0, 0, firstDiameter)]
        for index in 0..<segmentCount {
            let normalizedPosition = segmentCount == 1
                ? 0
                : (CGFloat(index * 2) - CGFloat(segmentCount - 1))
                    / CGFloat(segmentCount - 1)
            let angle = archAngle * normalizedPosition
            let distance = (diameters[index] + diameters[index + 1]) / 2
                + gap
            let previous = placements[index]
            placements.append(
                bubble(
                    previous.center.x + cos(angle) * distance,
                    previous.center.y + sin(angle) * distance,
                    diameters[index + 1]
                )
            )
        }

        return centeredHorizontally(placements)
    }

    private static func rowSeparation(
        upper: [EntryDetailPeopleBubblePlacement],
        lower: [EntryDetailPeopleBubblePlacement]
    ) -> CGFloat {
        var separation: CGFloat = 0
        for upperBubble in upper {
            for lowerBubble in lower {
                let requiredDistance =
                    (upperBubble.diameter + lowerBubble.diameter) / 2 + gap
                let deltaX = lowerBubble.center.x - upperBubble.center.x
                guard abs(deltaX) < requiredDistance else { continue }
                let tangentDeltaY = sqrt(
                    requiredDistance * requiredDistance - deltaX * deltaX
                )
                separation = max(
                    separation,
                    upperBubble.center.y - lowerBubble.center.y
                        + tangentDeltaY
                )
            }
        }
        return separation
    }

    private static func centeredHorizontally(
        _ placements: [EntryDetailPeopleBubblePlacement]
    ) -> [EntryDetailPeopleBubblePlacement] {
        let bounds = boundingRect(for: placements)
        return placements.map { placement in
            placement.offsetBy(x: -bounds.midX)
        }
    }

    private static func centered(
        _ placements: [EntryDetailPeopleBubblePlacement]
    ) -> [EntryDetailPeopleBubblePlacement] {
        guard !placements.isEmpty else { return [] }
        let bounds = boundingRect(for: placements)
        return placements.map { placement in
            placement.offsetBy(x: -bounds.midX, y: -bounds.midY)
        }
    }

    private static func bubble(
        _ x: CGFloat,
        _ y: CGFloat,
        _ diameter: CGFloat
    ) -> EntryDetailPeopleBubblePlacement {
        EntryDetailPeopleBubblePlacement(
            center: CGPoint(x: x, y: y),
            diameter: diameter
        )
    }
}

private extension EntryDetailPeopleBubblePlacement {
    nonisolated func offsetBy(x: CGFloat = 0, y: CGFloat = 0) -> Self {
        EntryDetailPeopleBubblePlacement(
            center: CGPoint(x: center.x + x, y: center.y + y),
            diameter: diameter
        )
    }
}
