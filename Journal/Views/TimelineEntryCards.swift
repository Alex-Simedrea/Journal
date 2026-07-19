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
        Button(action: onTap) {
            VStack(spacing: 7) {
                switch occurrence.kind {
                case .transit:
                    TimelineTransitCard(occurrence: occurrence)
                case .placeVisit:
                    TimelinePlaceVisitCard(occurrence: occurrence)
                case .workout:
                    TimelineWorkoutCard(occurrence: occurrence)
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

private struct TimelineTransitCard: View {
    let occurrence: TimelineOccurrence

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 6
            let typeWidth = (proxy.size.width - gap) * 0.42
            HStack(spacing: gap) {
                TimelineTransitTypeTile(occurrence: occurrence)
                    .frame(width: typeWidth)
                TimelinePlacesTile(
                    origin: occurrence.snapshot.originLocation,
                    originName: occurrence.origin,
                    destination: occurrence.snapshot.destinationLocation,
                    destinationName: occurrence.destination,
                    needsReview: occurrence.snapshot.reviews.contains {
                        $0.target == .origin || $0.target == .destination
                    }
                )
            }
        }
        .frame(height: 60)
    }
}

private struct TimelineTransitTypeTile: View {
    let occurrence: TimelineOccurrence

    private var presentation: TransitPresentation {
        TransitPresentationCatalog.presentation(for: occurrence.transitType)
    }

    var body: some View {
        HStack(spacing: 8) {
            TimelineFixedSymbol(
                systemName: presentation.systemImageName,
                size: 22,
                weight: .semibold
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.transitType)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                TimelineTransitMetrics(occurrence: occurrence)
            }
        }
        .foregroundStyle(presentation.foregroundColor)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(presentation.color, in: .rect(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            if occurrence.snapshot.reviews.contains(where: {
                $0.target == .transitType
            }) {
                TimelineReviewBadge().padding(5)
            }
        }
    }
}

private struct TimelineTransitMetrics: View {
    let occurrence: TimelineOccurrence

    var body: some View {
        HStack(spacing: 3) {
            if occurrence.snapshot.transitDistanceIsApproximate {
                Text("≈")
            }
            if let distance = occurrence.snapshot.transitDistanceMeters {
                Text(
                    Measurement(value: distance, unit: UnitLength.meters),
                    format: .measurement(width: .abbreviated)
                )
            }
            if let start = occurrence.startTime,
               let end = occurrence.endTime,
               end > start {
                Text("•")
                Text("\(Int((end.timeIntervalSince(start) / 60).rounded())) min")
            }
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

private struct TimelinePlaceVisitCard: View {
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
            let columnWidth = (proxy.size.width - gap * (columnCount - 1))
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

private struct TimelineVisitMiddleColumn: View {
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

private struct TimelineWorkoutCard: View {
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
                                location: occurrence.snapshot.workoutWeatherLocation,
                                timeZoneIdentifier: occurrence.timeZoneIdentifier
                            )
                            .frame(width: columnWidth, height: rowHeight)
                        }
                        .frame(height: rowHeight)

                        TimelinePlacesTile(
                            origin: occurrence.snapshot.workoutOriginLocation,
                            originName: occurrence.snapshot.workoutOrigin,
                            destination: occurrence.snapshot.workoutDestinationLocation,
                            destinationName: occurrence.snapshot.workoutDestination,
                            needsReview: occurrence.snapshot.reviews.contains {
                                $0.target == .origin || $0.target == .destination
                            }
                        )
                        .frame(height: rowHeight)
                    }
                    .frame(width: columnWidth * 2 + 6)
                }
            } else {
                let columnCount: CGFloat = hasStaticLocation ? 3 : 2
                let columnWidth = (
                    proxy.size.width - 6 * (columnCount - 1)
                ) / columnCount
                HStack(spacing: 6) {
                    if hasStaticLocation {
                        TimelineWorkoutMiniMap(occurrence: occurrence)
                            .frame(width: columnWidth, height: totalHeight)
                    }
                    TimelineWorkoutTypeTile(occurrence: occurrence)
                        .frame(width: columnWidth, height: totalHeight)
                    TimelineWeatherTile(
                        weather: occurrence.snapshot.weather,
                        layout: .large,
                        location: occurrence.snapshot.workoutWeatherLocation,
                        timeZoneIdentifier: occurrence.timeZoneIdentifier
                    )
                    .frame(width: columnWidth, height: totalHeight)
                }
                .frame(height: totalHeight, alignment: .top)
            }
        }
        .frame(height: rowHeight * 2 + 6)
    }
}

private struct TimelineWorkoutTypeTile: View {
    let occurrence: TimelineOccurrence

    var body: some View {
        HStack(spacing: 7) {
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
                if let energy = occurrence.snapshot.workoutActiveEnergyKilocalories {
                    Text("\(energy, format: .number.precision(.fractionLength(0))) kcal")
                        .font(.caption2.weight(.semibold))
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

private struct TimelinePlacesTile: View {
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

private struct TimelinePlaceEndpointRow: View {
    let name: String
    let systemImage: PlaceSystemImage

    var body: some View {
        HStack(spacing: 6) {
            TimelineFixedPlaceSymbol(systemImage: systemImage, size: 18)
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct TimelinePlaceMiniMap: View {
    let location: TimelineLocationSnapshot?
    let needsReview: Bool

    var body: some View {
        ZStack {
            if let location, location.hasCoordinate {
                Map(
                    initialPosition: .region(
                        MKCoordinateRegion(
                            center: location.coordinate,
                            latitudinalMeters: 320,
                            longitudinalMeters: 320
                        )
                    )
                ) {
                    Marker(
                        location.name,
                        systemImage: location.systemImage.rawValue,
                        coordinate: location.coordinate
                    )
                    .tint(PlaceSymbols.symbol(for: location.systemImage).primary)
                }
                .mapStyle(.standard)
            } else {
                TimelineMapUnavailableTile()
            }
        }
        .allowsHitTesting(false)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            if needsReview {
                TimelineReviewBadge().padding(5)
            }
        }
    }
}

private struct TimelineWorkoutMiniMap: View {
    let occurrence: TimelineOccurrence
    @State private var routeModel = WorkoutRouteModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            TimelineWorkoutMapContent(
                occurrence: occurrence,
                points: routeModel.points
            )

            if let distance = occurrence.snapshot.workoutDistanceMeters {
                Text(
                    Measurement(value: distance, unit: UnitLength.meters),
                    format: .measurement(width: .abbreviated)
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.58), in: .capsule)
                .padding(6)
            }
        }
        .allowsHitTesting(false)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            if occurrence.snapshot.reviews.contains(where: {
                $0.target == .place || $0.target == .origin
                    || $0.target == .destination
            }) {
                TimelineReviewBadge().padding(5)
            }
        }
        .task(id: occurrence.snapshot.workoutUUID) {
            guard occurrence.snapshot.workoutMovementKind == .moving,
                  let workoutUUID = occurrence.snapshot.workoutUUID else { return }
            await routeModel.load(workoutUUID: workoutUUID)
        }
    }
}

private struct TimelineWorkoutMapContent: View {
    let occurrence: TimelineOccurrence
    let points: [WorkoutCoordinateSnapshot]
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        if occurrence.snapshot.workoutMovementKind == .moving {
            Map(position: $position) {
                if points.count > 1 {
                    MapPolyline(coordinates: points.map(\.coordinate))
                        .stroke(
                            .black.opacity(0.5),
                            style: StrokeStyle(
                                lineWidth: 7,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    MapPolyline(coordinates: points.map(\.coordinate))
                        .stroke(
                            Color(hex: 0xB6FF00),
                            style: StrokeStyle(
                                lineWidth: 4,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                } else if let origin = workoutOrigin,
                          let destination = workoutDestination {
                    MapPolyline(
                        coordinates: [origin.coordinate, destination.coordinate]
                    )
                        .stroke(Color(hex: 0xB6FF00), lineWidth: 4)
                }

                if let origin = workoutOrigin {
                    Marker(
                        origin.name,
                        systemImage: origin.systemImage.rawValue,
                        coordinate: origin.coordinate
                    )
                    .tint(PlaceSymbols.symbol(for: origin.systemImage).primary)
                }
                if let destination = workoutDestination {
                    Marker(
                        destination.name,
                        systemImage: destination.systemImage.rawValue,
                        coordinate: destination.coordinate
                    )
                    .tint(
                        PlaceSymbols.symbol(for: destination.systemImage).primary
                    )
                }
            }
            .mapStyle(.standard)
            .onChange(of: points, initial: true) { _, points in
                position = routePosition(points: points)
            }
        } else if let location = workoutPlace {
            Map(
                initialPosition: .region(
                    MKCoordinateRegion(
                        center: location.coordinate,
                        latitudinalMeters: 320,
                        longitudinalMeters: 320
                    )
                )
            ) {
                Marker(
                    location.name,
                    systemImage: location.systemImage.rawValue,
                    coordinate: location.coordinate
                )
                .tint(PlaceSymbols.symbol(for: location.systemImage).primary)
            }
            .mapStyle(.standard)
        } else {
            TimelineMapUnavailableTile()
        }
    }

    private var workoutOrigin: TimelineWorkoutMapEndpoint? {
        guard let coordinate = points.first?.coordinate
            ?? occurrence.snapshot.workoutRouteStart?.coordinate else {
            return nil
        }
        return TimelineWorkoutMapEndpoint(
            name: occurrence.snapshot.workoutOrigin,
            systemImage: occurrence.snapshot.workoutOriginLocation?.systemImage
                ?? .mappin,
            coordinate: coordinate
        )
    }

    private var workoutDestination: TimelineWorkoutMapEndpoint? {
        guard let coordinate = points.last?.coordinate
            ?? occurrence.snapshot.workoutRouteEnd?.coordinate else {
            return nil
        }
        return TimelineWorkoutMapEndpoint(
            name: occurrence.snapshot.workoutDestination,
            systemImage:
                occurrence.snapshot.workoutDestinationLocation?.systemImage
                    ?? .mappin,
            coordinate: coordinate
        )
    }

    private var workoutPlace: TimelineWorkoutMapEndpoint? {
        guard let coordinate = occurrence.snapshot.workoutRouteStart?.coordinate
            ?? occurrence.snapshot.workoutPlaceLocation?.coordinate else {
            return nil
        }
        return TimelineWorkoutMapEndpoint(
            name: occurrence.snapshot.workoutPlace,
            systemImage: occurrence.snapshot.workoutPlaceLocation?.systemImage
                ?? .mappin,
            coordinate: coordinate
        )
    }

    private func routePosition(
        points: [WorkoutCoordinateSnapshot]
    ) -> MapCameraPosition {
        var coordinates = points.map(\.coordinate)
        if coordinates.count < 2 {
            coordinates = [workoutOrigin, workoutDestination]
                .compactMap { $0?.coordinate }
        }
        guard let first = coordinates.first else { return .automatic }
        guard coordinates.count > 1 else {
            return .region(
                MKCoordinateRegion(
                    center: first,
                    latitudinalMeters: 320,
                    longitudinalMeters: 320
                )
            )
        }

        let mapPoints = coordinates.map(MKMapPoint.init)
        let minX = mapPoints.map(\.x).min() ?? 0
        let maxX = mapPoints.map(\.x).max() ?? minX
        let minY = mapPoints.map(\.y).min() ?? 0
        let maxY = mapPoints.map(\.y).max() ?? minY
        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(first.latitude)
        let horizontalPadding = max((maxX - minX) * 0.12, pointsPerMeter * 90)
        let verticalPadding = max((maxY - minY) * 0.12, pointsPerMeter * 90)
        let rect = MKMapRect(
            x: minX - horizontalPadding,
            y: minY - verticalPadding,
            width: maxX - minX + horizontalPadding * 2,
            height: maxY - minY + verticalPadding * 2
        )
        return .rect(rect)
    }
}

private struct TimelineWorkoutMapEndpoint {
    let name: String
    let systemImage: PlaceSystemImage
    let coordinate: CLLocationCoordinate2D
}

private struct TimelineMapUnavailableTile: View {
    var body: some View {
        ZStack {
            Color(uiColor: .tertiarySystemGroupedBackground)
            TimelineFixedSymbol(systemName: "map", size: 24)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Location unavailable")
    }
}

private enum TimelineWeatherTileLayout {
    case compact
    case large
}

private struct TimelineWeatherTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let weather: EntryWeather?
    let layout: TimelineWeatherTileLayout
    let location: TimelineLocationSnapshot?
    let timeZoneIdentifier: String

    var body: some View {
        ZStack {
            if let weather {
                switch layout {
                case .compact:
                    TimelineCompactWeatherContent(weather: weather)
                case .large:
                    TimelineLargeWeatherContent(weather: weather)
                }
            } else {
                TimelineUnavailableWeatherContent(layout: layout)
            }
        }
        .foregroundStyle(.white)
        .padding(layout == .large ? 10 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            TimelineWeatherGradient.gradient(
                weather: weather,
                location: location,
                timeZoneIdentifier: timeZoneIdentifier,
                colorScheme: colorScheme
            ),
            in: .rect(cornerRadius: 16)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct TimelineCompactWeatherContent: View {
    let weather: EntryWeather

    var body: some View {
        HStack(spacing: 7) {
            TimelineWeatherSymbol(symbolName: weather.symbolName, size: 26)

            VStack(alignment: .leading, spacing: 0) {
                TimelineTemperatureLabel(celsius: weather.temperatureCelsius)
                .font(.title3.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.68)

                TimelineHumidityLabel(humidity: weather.humidity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct TimelineLargeWeatherContent: View {
    let weather: EntryWeather

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineWeatherSymbol(symbolName: weather.symbolName, size: 32)

            Spacer(minLength: 2)

            TimelineTemperatureLabel(celsius: weather.temperatureCelsius)
            .font(.title3.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            TimelineHumidityLabel(humidity: weather.humidity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct TimelineTemperatureLabel: View {
    let celsius: Double

    var body: some View {
        Text(
            "\(celsius, format: .number.precision(.fractionLength(0)))°C"
        )
    }
}

private struct TimelineHumidityLabel: View {
    let humidity: Double

    var body: some View {
        HStack(spacing: 3) {
            TimelineFixedSymbol(systemName: "humidity.fill", size: 13)
            Text(humidity, format: .percent.precision(.fractionLength(0)))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white.opacity(0.82))
        .lineLimit(1)
    }
}

private struct TimelineUnavailableWeatherContent: View {
    let layout: TimelineWeatherTileLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TimelineFixedSymbol(
                systemName: "cloud.slash.fill",
                size: layout == .large ? 30 : 24
            )
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .cyan)
            if layout == .large {
                Spacer(minLength: 4)
            }
            Text("Weather unavailable")
                .font(.caption.weight(.semibold))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct TimelineWeatherSymbol: View {
    let symbolName: String
    let size: CGFloat

    var body: some View {
        let palette = TimelineWeatherSymbolPalette.colors(for: symbolName)
        Image(systemName: symbolName)
            .resizable()
            .scaledToFit()
            .symbolVariant(.fill)
            .symbolRenderingMode(.palette)
            .foregroundStyle(palette.primary, palette.secondary, palette.tertiary)
            .fontWeight(.semibold)
            .frame(width: size, height: size)
    }
}

private enum TimelineWeatherSymbolPalette {
    static func colors(
        for symbolName: String
    ) -> (primary: Color, secondary: Color, tertiary: Color) {
        if symbolName.contains("bolt") {
            return (.yellow, .white, .purple)
        }
        if symbolName.contains("rain") || symbolName.contains("drizzle") {
            return (.white, .cyan, .blue)
        }
        if symbolName.contains("snow") || symbolName.contains("sleet") {
            return (.white, .cyan, .blue)
        }
        if symbolName.contains("cloud") && symbolName.contains("sun") {
            return (.white, .yellow, .cyan)
        }
        if symbolName.contains("cloud") || symbolName.contains("fog") {
            return (.white, .cyan, .blue)
        }
        if symbolName.contains("sun") {
            return (.yellow, .orange, .white)
        }
        return (.white, .cyan, .blue)
    }
}

private enum TimelineWeatherGradient {
    static func gradient(
        weather: EntryWeather?,
        location: TimelineLocationSnapshot?,
        timeZoneIdentifier: String,
        colorScheme: ColorScheme
    ) -> LinearGradient {
        let symbolName = weather?.symbolName ?? "cloud.slash.fill"
        let phase = TimelineWeatherPresentation.skyPhase(
            date: weather?.date ?? .now,
            latitude: location?.latitude,
            longitude: location?.longitude,
            symbolName: symbolName,
            timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current
        )
        let colors = TimelineWeatherPresentation.gradientHexes(
            symbolName: symbolName,
            phase: phase
        )
        let factor = colorScheme == .dark ? 0.82 : 1
        return LinearGradient(
            colors: colors.map {
                Color(hex: scaled($0, factor: factor))
            },
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private static func scaled(_ hex: UInt32, factor: Double) -> UInt32 {
        let red = UInt32(Double((hex >> 16) & 0xff) * factor)
        let green = UInt32(Double((hex >> 8) & 0xff) * factor)
        let blue = UInt32(Double(hex & 0xff) * factor)
        return (red << 16) | (green << 8) | blue
    }
}

private struct TimelineFixedSymbol: View {
    let systemName: String
    let size: CGFloat
    let weight: Font.Weight

    init(
        systemName: String,
        size: CGFloat,
        weight: Font.Weight = .regular
    ) {
        self.systemName = systemName
        self.size = size
        self.weight = weight
    }

    var body: some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .fontWeight(weight)
            .frame(width: size, height: size)
    }
}

private struct TimelineFixedPlaceSymbol: View {
    let systemImage: PlaceSystemImage
    let size: CGFloat

    var body: some View {
        let symbol = PlaceSymbols.symbol(for: systemImage)
        Image(systemName: symbol.systemImage.rawValue)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                symbol.primary.gradient,
                symbol.secondary.gradient,
                symbol.tertiary.gradient
            )
            .frame(width: size, height: size)
    }
}

private struct TimelinePeopleTile: View {
    let people: [TimelinePersonSnapshot]
    let needsReview: Bool

    var body: some View {
        HStack(spacing: 7) {
            if people.isEmpty {
                TimelineFixedSymbol(
                    systemName: "person.crop.circle.badge.questionmark",
                    size: 22
                )
                Text("People need review")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
            } else if people.count <= 2 {
                ForEach(people) { person in
                    TimelineNamedPerson(person: person)
                }
            } else if let first = people.first {
                TimelineNamedPerson(person: first)
                TimelinePeopleSummary(people: Array(people.dropFirst()))
            }
        }
        .padding(.horizontal, 8)
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

private struct TimelineNamedPerson: View {
    let person: TimelinePersonSnapshot

    var body: some View {
        HStack(spacing: 4) {
            PersonAvatar(
                name: person.name,
                contactIdentifier: person.contactIdentifier,
                size: 24
            )
            Text(person.name)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TimelinePeopleSummary: View {
    let people: [TimelinePersonSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: -8) {
                ForEach(people.prefix(3)) { person in
                    PersonAvatar(
                        name: person.name,
                        contactIdentifier: person.contactIdentifier,
                        size: 22
                    )
                    .overlay { Circle().stroke(.background, lineWidth: 1.5) }
                }
            }
            Text("\(people.count) more")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct TimelinePhotoTile: View {
    let references: [PhotoReference]

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
    ]

    var body: some View {
        if references.count == 1, let reference = references.first {
            TimelinePhotoThumbnail(reference: reference)
                .clipShape(.rect(cornerRadius: 16))
        } else {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(references.prefix(4).enumerated(), id: \.element.id) {
                    index, reference in
                    TimelinePhotoThumbnail(reference: reference)
                        .overlay {
                            if index == 3, references.count > 4 {
                                ZStack {
                                    Color.black.opacity(0.52)
                                    Text("+\(references.count - 4)")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .clipShape(.rect(cornerRadius: 9))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color(uiColor: .tertiarySystemGroupedBackground),
                in: .rect(cornerRadius: 16)
            )
        }
    }
}

private struct TimelinePhotoThumbnail: View {
    @Environment(\.displayScale) private var displayScale
    let reference: PhotoReference
    @State private var image: UIImage?
    @State private var didFinishLoading = false

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if didFinishLoading {
                TimelineFixedSymbol(
                    systemName: "photo.badge.exclamationmark",
                    size: 24
                )
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .clipped()
        .task(id: reference.assetLocalIdentifier) {
            didFinishLoading = false
            image = await PhotoLibraryService.image(
                for: reference.assetLocalIdentifier,
                targetSize: CGSize(
                    width: 180 * displayScale,
                    height: 180 * displayScale
                )
            )
            didFinishLoading = true
        }
    }
}

private struct TimelineUnmatchedReviewStrip: View {
    let occurrence: TimelineOccurrence

    private var reviews: [TimelineReviewSnapshot] {
        let mapped: Set<TimelineReviewTarget> = switch occurrence.kind {
        case .transit: [.transitType, .origin, .destination, .time]
        case .placeVisit: [.place, .people, .time]
        case .workout: [.place, .origin, .destination]
        }
        return occurrence.snapshot.reviews.filter { !mapped.contains($0.target) }
    }

    var body: some View {
        if !reviews.isEmpty {
            HStack(spacing: 6) {
                TimelineReviewBadge()
                Text(reviews.map(\.target.title).formatted())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        }
    }
}

private extension TimelineReviewTarget {
    var title: String {
        switch self {
        case .entryKind: String(localized: "Entry type needs review")
        case .transitType: String(localized: "Transit type needs review")
        case .origin: String(localized: "Origin needs review")
        case .destination: String(localized: "Destination needs review")
        case .place: String(localized: "Place needs review")
        case .time: String(localized: "Time needs review")
        case .people: String(localized: "People need review")
        }
    }
}
