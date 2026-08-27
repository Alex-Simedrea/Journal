import SwiftData
import SwiftUI

struct EntryDetailOverview: View {
    let entry: LogEntry
    let peopleOverride: [Person]?
    let routeModel: WorkoutRouteModel
    let topContentInset: CGFloat
    @Binding var isScrolled: Bool
    let onPresent: (EntryDetailRoute) -> Void
    let showsDestructiveActions: Bool
    let showsDismissAction: Bool

    var body: some View {
        DynamicSheetScrollView(
            topContentInset: topContentInset,
            isScrolled: $isScrolled
        ) {
            VStack(spacing: 10) {
                EntryDetailMapCard(
                    entry: entry,
                    routeModel: routeModel,
                    needsReview: mapNeedsReview,
                    onEdit: editMap
                )

                switch entry.kind {
                case .placeVisit:
                    EntryDetailPlaceComposition(
                        entry: entry,
                        people: peopleOverride ?? entry.people,
                        onPresent: onPresent
                    )
                case .transit:
                    EntryDetailTransitComposition(
                        entry: entry,
                        people: peopleOverride ?? entry.people,
                        onPresent: onPresent
                    )
                case .workout:
                    EntryDetailWorkoutComposition(
                        entry: entry,
                        people: peopleOverride ?? entry.people,
                        onPresent: onPresent
                    )
                case .wakeUp:
                    ContentUnavailableView(
                        "Wake-up Details",
                        systemImage: "alarm"
                    )
                }

                DisclosureSectionButton(
                    title: "Photos",
                    onSelect: { onPresent(.photos) }
                )
                EntryDetailPhotoGrid(references: entry.photoReferences)

                if showsDestructiveActions {
                    Button {
                        onPresent(.advanced)
                    } label: {
                        HStack {
                            Label("Advanced", systemImage: "hammer")
                            Spacer()
                            DisclosureChevron()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.background, in: .rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 24)

                    EntryDetailDestructiveButton(
                        title: "Delete entry",
                        action: {
                            onPresent(
                                .destructiveConfirmation(.deleteEntry)
                            )
                        }
                    )
                }

                if showsDismissAction {
                    EntryDetailDestructiveButton(
                        title: "Dismiss Candidate",
                        action: {
                            onPresent(
                                .destructiveConfirmation(.dismissCandidate)
                            )
                        }
                    )
                    .padding(.top, 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
    }

    private func editMap() {
        onPresent(
            EntryDetailLocationRouting.editRoute(
                for: entry.kind,
                workoutMovementKind: entry.workoutDetails?.movementKind
            )
        )
    }

    private func transitNeedsReview(_ field: TransitReviewField) -> Bool {
        entry.transitDetails?.review(for: field) != nil
    }

    private func placeNeedsReview(_ field: PlaceVisitReviewField) -> Bool {
        entry.placeVisitDetails?.review(for: field) != nil
    }

    private var mapNeedsReview: Bool {
        switch entry.kind {
        case .transit:
            return transitNeedsReview(.origin)
                || transitNeedsReview(.destination)
        case .placeVisit:
            return placeNeedsReview(.place)
        case .workout:
            guard let details = entry.workoutDetails else { return false }
            return !details.fieldReviews.isEmpty
        case .wakeUp:
            return false
        }
    }

}

private struct EntryDetailDestructiveButton: View {
    let title: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: "trash")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background, in: .rect(cornerRadius: 16))
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
    }
}

extension LogKind {
    var detailTitle: LocalizedStringResource {
        switch self {
        case .transit: "Transit"
        case .placeVisit: "Place"
        case .workout: "Workout"
        case .wakeUp: "Wake Up"
        }
    }
}
