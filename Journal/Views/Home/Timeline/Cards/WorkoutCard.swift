import MapKit
import Photos
import SwiftUI

struct TimelineWorkoutCard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let occurrence: TimelineOccurrence

    private var rowHeight: CGFloat {
        horizontalSizeClass == .regular ? 72 : 52
    }

    private var isMoving: Bool {
        occurrence.snapshot.workoutMovementKind == .moving
    }

    private var hasStaticLocation: Bool {
        occurrence.snapshot.workoutPlaceLocation?.hasCoordinate == true
    }

    var body: some View {
        GeometryReader { proxy in
            let totalHeight = rowHeight * 2 + 6
            if isMoving {
                let columnWidth = (proxy.size.width - 12) / 3
                HStack(spacing: 6) {
                    TimelineWorkoutMiniMap(occurrence: occurrence)
                        .frame(width: columnWidth, height: totalHeight)

                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            TimelineWorkoutTypeTile(occurrence: occurrence)
                                .frame(width: columnWidth, height: rowHeight)
                            TimelineWeatherTile(
                                weather: occurrence.snapshot.weather,
                                layout: .compact,
                                location: occurrence.snapshot
                                    .workoutWeatherLocation,
                                timeZoneIdentifier: occurrence
                                    .timeZoneIdentifier
                            )
                            .frame(width: columnWidth, height: rowHeight)
                        }
                        .frame(height: rowHeight)

                        TimelineWorkoutPlacesAndPeopleRow(
                            occurrence: occurrence
                        )
                        .frame(height: rowHeight)
                    }
                    .frame(width: columnWidth * 2 + 6)
                }
            } else {
                let columnCount: CGFloat = hasStaticLocation ? 3 : 2
                let columnWidth =
                    (proxy.size.width - 6 * (columnCount - 1)) / columnCount
                HStack(spacing: 6) {
                    if hasStaticLocation {
                        TimelineWorkoutMiniMap(occurrence: occurrence)
                            .frame(width: columnWidth, height: totalHeight)
                    }
                    TimelineWorkoutTypeTile(occurrence: occurrence)
                        .frame(width: columnWidth, height: totalHeight)
                    TimelineWorkoutWeatherAndPeopleColumn(
                        weather: occurrence.snapshot.weather,
                        location: occurrence.snapshot.workoutWeatherLocation,
                        timeZoneIdentifier: occurrence.timeZoneIdentifier,
                        people: occurrence.snapshot.people,
                        rowHeight: rowHeight
                    )
                    .frame(width: columnWidth, height: totalHeight)
                }
                .frame(height: totalHeight, alignment: .top)
            }
        }
        .frame(height: rowHeight * 2 + 6)
    }
}

struct TimelineWorkoutPlacesAndPeopleRow: View {
    let occurrence: TimelineOccurrence

    var body: some View {
        HStack(spacing: 6) {
            TimelinePlacesTile(
                origin: occurrence.snapshot.workoutOriginLocation,
                originName: occurrence.snapshot.workoutOrigin,
                destination: occurrence.snapshot.workoutDestinationLocation,
                destinationName: occurrence.snapshot.workoutDestination,
                needsReview: occurrence.snapshot.reviews.contains {
                    $0.target == .origin || $0.target == .destination
                }
            )

            if !occurrence.snapshot.people.isEmpty {
                TimelinePeopleTile(
                    people: occurrence.snapshot.people,
                    needsReview: false
                )
            }
        }
    }
}

struct TimelineWorkoutWeatherAndPeopleColumn: View {
    let weather: EntryWeather?
    let location: TimelineLocationSnapshot?
    let timeZoneIdentifier: String
    let people: [TimelinePersonSnapshot]
    let rowHeight: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            TimelineWeatherTile(
                weather: weather,
                layout: people.isEmpty ? .large : .compact,
                location: location,
                timeZoneIdentifier: timeZoneIdentifier
            )
            .frame(
                height: people.isEmpty ? rowHeight * 2 + 6 : rowHeight
            )

            if !people.isEmpty {
                TimelinePeopleTile(people: people, needsReview: false)
                    .frame(height: rowHeight)
            }
        }
    }
}

struct TimelineWorkoutTypeTile: View {
    let occurrence: TimelineOccurrence

    var body: some View {
        HStack(spacing: 4) {
            TimelineFixedSymbol(
                systemName: occurrence.snapshot.workoutSystemImageName,
                size: 22,
                weight: .semibold
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(occurrence.snapshot.workoutActivityName)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if let energy = occurrence.snapshot
                    .workoutActiveEnergyKilocalories
                {
                    Text(
                        "\(energy, format: .number.precision(.fractionLength(0))) kcal"
                    )
                    .font(.footnote.weight(.medium))
                    .opacity(0.8)
                    .lineLimit(1)
                }
            }
        }
        .foregroundStyle(.black)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(hex: 0xB6FF00), in: .rect(cornerRadius: 16))
    }
}

struct TimelinePlacesTile: View {
    let origin: TimelineLocationSnapshot?
    let originName: String
    let destination: TimelineLocationSnapshot?
    let destinationName: String
    let needsReview: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelinePlaceEndpointRow(
                name: originName,
                systemImage: origin?.systemImage ?? .mappin
            )
            TimelinePlaceEndpointRow(
                name: destinationName,
                systemImage: destination?.systemImage ?? .mappin
            )
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .tertiarySystemGroupedBackground),
            in: .rect(cornerRadius: 16)
        )
        .overlay(alignment: .topTrailing) {
            if needsReview {
                TimelineReviewBadge().padding(5)
            }
        }
    }
}

struct TimelinePlaceEndpointRow: View {
    let name: String
    let systemImage: PlaceSystemImage

    var body: some View {
        HStack(spacing: 6) {
            TimelineFixedPlaceSymbol(systemImage: systemImage, size: 18)
            Text(name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}
