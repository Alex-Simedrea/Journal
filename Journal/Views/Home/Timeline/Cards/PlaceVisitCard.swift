import MapKit
import Photos
import SwiftUI

enum TimelinePlaceVisitCardLayout {
    static let compactMapCameraNorthOffsetFraction = 0.10

    static func rowCount(
        hasPeople: Bool,
        peopleNeedReview: Bool,
        photoCount: Int
    ) -> Int {
        hasPeople || peopleNeedReview || photoCount >= 3 ? 2 : 1
    }

    static func mapCameraNorthOffsetFraction(rowCount: Int) -> Double {
        rowCount == 1 ? compactMapCameraNorthOffsetFraction : 0
    }

    static func weatherRowCount(
        cardRowCount: Int,
        showsPeople: Bool
    ) -> Int {
        showsPeople ? 1 : cardRowCount
    }
}

struct TimelinePlaceVisitCard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let occurrence: TimelineOccurrence

    private var rowHeight: CGFloat {
        horizontalSizeClass == .regular ? 72 : 52
    }

    private var peopleNeedReview: Bool {
        occurrence.snapshot.reviews.contains { $0.target == .people }
    }

    private var rowCount: Int {
        TimelinePlaceVisitCardLayout.rowCount(
            hasPeople: !occurrence.snapshot.people.isEmpty,
            peopleNeedReview: peopleNeedReview,
            photoCount: occurrence.snapshot.photoReferences.count
        )
    }

    private var totalHeight: CGFloat {
        rowHeight * CGFloat(rowCount) + (rowCount == 2 ? 6 : 0)
    }

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 6
            let hasPhotos = !occurrence.snapshot.photoReferences.isEmpty
            let columnCount: CGFloat = hasPhotos ? 3 : 2
            let columnWidth =
                (proxy.size.width - gap * (columnCount - 1))
                / columnCount

            HStack(spacing: gap) {
                TimelinePlaceMiniMap(
                    location: occurrence.snapshot.visitLocation,
                    needsReview: false,
                    cameraNorthOffsetFraction: TimelinePlaceVisitCardLayout
                        .mapCameraNorthOffsetFraction(rowCount: rowCount)
                )
                .frame(width: columnWidth, height: totalHeight)

                TimelineVisitMiddleColumn(
                    weather: occurrence.snapshot.weather,
                    location: occurrence.snapshot.visitLocation,
                    timeZoneIdentifier: occurrence.timeZoneIdentifier,
                    people: occurrence.snapshot.people,
                    peopleNeedReview: peopleNeedReview,
                    rowHeight: rowHeight,
                    cardRowCount: rowCount
                )
                .frame(width: columnWidth, height: totalHeight)

                if hasPhotos {
                    TimelinePhotoTile(
                        references: occurrence.snapshot.photoReferences
                    )
                    .frame(width: columnWidth, height: totalHeight)
                    .clipShape(.rect(cornerRadius: 16))
                }
            }
            .frame(height: totalHeight, alignment: .top)
        }
        .frame(height: totalHeight)
    }
}

struct TimelineVisitMiddleColumn: View {
    let weather: EntryWeather?
    let location: TimelineLocationSnapshot?
    let timeZoneIdentifier: String
    let people: [TimelinePersonSnapshot]
    let peopleNeedReview: Bool
    let rowHeight: CGFloat
    let cardRowCount: Int

    private var showsPeople: Bool {
        !people.isEmpty || peopleNeedReview
    }

    private var weatherRowCount: Int {
        TimelinePlaceVisitCardLayout.weatherRowCount(
            cardRowCount: cardRowCount,
            showsPeople: showsPeople
        )
    }

    var body: some View {
        VStack(spacing: 6) {
            TimelineWeatherTile(
                weather: weather,
                layout: weatherRowCount == 1 ? .compact : .large,
                location: location,
                timeZoneIdentifier: timeZoneIdentifier
            )
            .frame(
                height: rowHeight * CGFloat(weatherRowCount)
                    + (weatherRowCount == 2 ? 6 : 0)
            )

            if showsPeople {
                TimelinePeopleTile(
                    people: people,
                    needsReview: false
                )
                .frame(height: rowHeight)
            }
        }
    }
}
