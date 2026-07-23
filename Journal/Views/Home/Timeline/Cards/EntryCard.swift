//
//  TimelineEntryCards.swift
//  Journal
//

import MapKit
import Photos
import SwiftUI

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
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: .rect(cornerRadius: 22)
            )
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens entry details")
    }
}
