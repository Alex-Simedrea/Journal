//
//  TimelineEntryCards.swift
//  Journal
//

import MapKit
import Photos
import SwiftUI

enum TimelineEntryCardReviewPresentation {
    static func showsOrangeInnerShadow(
        kind: LogKind,
        needsReview: Bool
    ) -> Bool {
        kind == .placeVisit && needsReview
    }
}

struct TimelineEntryCard: View {
    let occurrence: TimelineOccurrence
    let onTap: () -> Void

    var body: some View {
        if occurrence.kind == .wakeUp {
            TimelineWakeUpRow(occurrence: occurrence)
        } else {
            TimelineInteractiveEntryCard(
                occurrence: occurrence,
                onTap: onTap
            )
        }
    }
}

struct TimelineInteractiveEntryCard: View {
    let occurrence: TimelineOccurrence
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 7) {
                switch occurrence.kind {
                case .transit:
                    TimelineTransitCard(occurrence: occurrence)
                case .placeVisit:
                    TimelinePlaceVisitCard(occurrence: occurrence)
                case .workout:
                    TimelineWorkoutCard(occurrence: occurrence)
                case .wakeUp:
                    TimelineWakeUpRow(occurrence: occurrence)
                }

                TimelineUnmatchedReviewStrip(occurrence: occurrence)
            }
            .padding(7)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        Color(uiColor: .secondarySystemGroupedBackground)
                            .shadow(
                                .inner(
                                    color: Color.orange.opacity(
                                        TimelineEntryCardReviewPresentation
                                            .showsOrangeInnerShadow(
                                                kind: occurrence.kind,
                                                needsReview: occurrence.needsReview
                                            ) ? 1 : 0
                                    ),
                                    radius: 3
                                )
                            )
                    )
                    .allowsHitTesting(false)
            }
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens entry details")
    }
}
