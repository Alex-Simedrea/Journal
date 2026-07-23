import MapKit
import Photos
import SwiftUI

struct TimelinePlaceVisitCard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let occurrence: TimelineOccurrence

    private var rowHeight: CGFloat {
        horizontalSizeClass == .regular ? 72 : 52
    }

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 6
            let totalHeight = rowHeight * 2 + gap
            let hasPhotos = !occurrence.snapshot.photoReferences.isEmpty
            let columnCount: CGFloat = hasPhotos ? 3 : 2
            let columnWidth =
                (proxy.size.width - gap * (columnCount - 1))
                / columnCount

            HStack(spacing: gap) {
                TimelinePlaceMiniMap(
                    location: occurrence.snapshot.visitLocation,
                    needsReview: occurrence.snapshot.reviews.contains {
                        $0.target == .place
                    }
                )
                .frame(width: columnWidth, height: totalHeight)

                TimelineVisitMiddleColumn(
                    weather: occurrence.snapshot.weather,
                    location: occurrence.snapshot.visitLocation,
                    timeZoneIdentifier: occurrence.timeZoneIdentifier,
                    people: occurrence.snapshot.people,
                    peopleNeedReview: occurrence.snapshot.reviews.contains {
                        $0.target == .people
                    },
                    rowHeight: rowHeight
                )
                .frame(width: columnWidth, height: totalHeight)

                if hasPhotos {
                    TimelinePhotoTile(
                        references: occurrence.snapshot.photoReferences
                    )
                    .frame(width: columnWidth, height: totalHeight)
                }
            }
            .frame(height: totalHeight, alignment: .top)
        }
        .frame(height: rowHeight * 2 + 6)
    }
}

struct TimelineVisitMiddleColumn: View {
    let weather: EntryWeather?
    let location: TimelineLocationSnapshot?
    let timeZoneIdentifier: String
    let people: [TimelinePersonSnapshot]
    let peopleNeedReview: Bool
    let rowHeight: CGFloat

    private var showsPeople: Bool {
        !people.isEmpty || peopleNeedReview
    }

    var body: some View {
        VStack(spacing: 6) {
            TimelineWeatherTile(
                weather: weather,
                layout: showsPeople ? .compact : .large,
                location: location,
                timeZoneIdentifier: timeZoneIdentifier
            )
            .frame(height: showsPeople ? rowHeight : rowHeight * 2 + 6)

            if showsPeople {
                TimelinePeopleTile(
                    people: people,
                    needsReview: peopleNeedReview
                )
                .frame(height: rowHeight)
            }
        }
    }
}
