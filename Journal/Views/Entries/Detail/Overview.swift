import SwiftData
import SwiftUI

struct EntryDetailOverview: View {
  let entry: LogEntry
  let routeModel: WorkoutRouteModel
  let topContentInset: CGFloat
  @Binding var isScrolled: Bool
  let onPresent: (EntryDetailRoute) -> Void
  let onDelete: () -> Void

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
            onPresent: onPresent
          )
        case .transit:
          EntryDetailTransitComposition(
            entry: entry,
            onPresent: onPresent
          )
        case .workout:
          EntryDetailWorkoutComposition(
            entry: entry,
            onPresent: onPresent
          )
        case .wakeUp:
          ContentUnavailableView(
            "Wake-up Details",
            systemImage: "alarm"
          )
        }

        EntryDetailSectionButton(
          title: "Photos",
          onSelect: { onPresent(.photos) }
        )
        EntryDetailPhotoGrid(references: entry.photoReferences)

        Button {
          onPresent(.advanced)
        } label: {
          HStack {
            Label("Advanced", systemImage: "hammer")
            Spacer()
            EntryDetailChevron()
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
          .background(.background, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.top, 24)
        Button {
          onDelete()
        } label: {
          Label("Delete entry", systemImage: "trash")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background, in: .rect(cornerRadius: 16))
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)

      }
      .padding(.horizontal, 16)
      .padding(.bottom, 18)
    }
  }

  private func editMap() {
    if entry.kind == .placeVisit
      || entry.workoutDetails?.movementKind != .moving
    {
      onPresent(.location(.place))
    } else {
      onPresent(.locations)
    }
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
