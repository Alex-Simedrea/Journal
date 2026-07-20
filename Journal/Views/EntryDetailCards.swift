//
//  EntryDetailCards.swift
//  Journal
//

import MapKit
import Photos
import SwiftUI

struct EntryDetailMapCard: View {
    let entry: LogEntry
    let routeModel: WorkoutRouteModel
    let needsReview: Bool
    let onEdit: () -> Void

    var body: some View {
        EntryDetailMapContent(entry: entry, points: routeModel.points)
            .aspectRatio(
                entry.kind == .placeVisit ? 2.35 : 1.57,
                contentMode: .fit
            )
            .clipShape(.rect(cornerRadius: 22))
            .overlay(alignment: .topTrailing) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.title3.weight(.medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .padding(.top, 12)
                .padding(.trailing, 12)
                .accessibilityLabel("Edit locations")
            }
            .overlay(alignment: .bottomTrailing) {
                if needsReview {
                    EntryDetailReviewBadge()
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                }
            }
            .task(id: workoutUUID) {
                guard let workoutUUID else { return }
                await routeModel.load(workoutUUID: workoutUUID)
            }
    }

    private var workoutUUID: UUID? {
        guard entry.kind == .workout,
            entry.workoutDetails?.movementKind == .moving
        else {
            return nil
        }
        return entry.workoutDetails?.healthKitWorkoutUUID
    }
}

private struct EntryDetailMapContent: View {
    let entry: LogEntry
    let points: [WorkoutCoordinateSnapshot]

    var body: some View {
        Map(initialPosition: initialPosition, interactionModes: []) {
            switch entry.kind {
            case .placeVisit:
                if let endpoint = visitEndpoint {
                    EntryDetailMapMarker(endpoint: endpoint)
                }
            case .transit:
                if let origin = transitOrigin,
                    let destination = transitDestination
                {
                    MapPolyline(
                        coordinates: TimelineOverviewData.curvedCoordinates(
                            from: origin.location.coordinate,
                            to: destination.location.coordinate,
                            bendPositive: true
                        )
                    )
                    .stroke(
                        TransitPresentationCatalog.presentation(
                            for: entry.transitDetails?.type ?? "Transit"
                        ).color.opacity(0.82),
                        style: StrokeStyle(
                            lineWidth: 4,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
                if let transitOrigin {
                    EntryDetailMapMarker(endpoint: transitOrigin)
                }
                if let transitDestination {
                    EntryDetailMapMarker(endpoint: transitDestination)
                }
            case .workout:
                if points.count > 1 {
                    MapPolyline(coordinates: points.map(\.coordinate))
                        .stroke(
                            .black.opacity(0.48),
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
                }
                if let workoutOrigin {
                    EntryDetailMapMarker(endpoint: workoutOrigin)
                }
                if let workoutDestination {
                    EntryDetailMapMarker(endpoint: workoutDestination)
                }
                if points.isEmpty, let workoutPlace {
                    EntryDetailMapMarker(endpoint: workoutPlace)
                }
            case .wakeUp:
                EmptyMapContent()
            }
        }
        .mapStyle(.standard)
        .allowsHitTesting(false)
    }

    private var initialPosition: MapCameraPosition {
        guard entry.kind == .placeVisit, let visitEndpoint else {
            return .automatic
        }
        return .region(
            MKCoordinateRegion(
                center: visitEndpoint.location.coordinate,
                latitudinalMeters: 700,
                longitudinalMeters: 700
            )
        )
    }

    private var visitEndpoint: EntryDetailMapEndpoint? {
        guard let details = entry.placeVisitDetails,
            let location = details.location ?? details.place?.location
        else {
            return nil
        }
        return EntryDetailMapEndpoint(
            name: details.place?.name ?? location.preferredName ?? "Place",
            location: location,
            systemImage: details.place?.systemImage ?? .mappin
        )
    }

    private var transitOrigin: EntryDetailMapEndpoint? {
        guard let details = entry.transitDetails,
            let location = details.originLocation
                ?? details.originPlace?.location
        else { return nil }
        return EntryDetailMapEndpoint(
            name: details.originPlace?.name
                ?? location.preferredName
                ?? "Origin",
            location: location,
            systemImage: details.originPlace?.systemImage ?? .mappin
        )
    }

    private var transitDestination: EntryDetailMapEndpoint? {
        guard let details = entry.transitDetails,
            let location = details.destinationLocation
                ?? details.destinationPlace?.location
        else { return nil }
        return EntryDetailMapEndpoint(
            name: details.destinationPlace?.name
                ?? location.preferredName
                ?? "Destination",
            location: location,
            systemImage: details.destinationPlace?.systemImage ?? .mappin
        )
    }

    private var workoutOrigin: EntryDetailMapEndpoint? {
        guard entry.workoutDetails?.movementKind == .moving,
            let location = points.first.map({ point in
                Location(
                    latitude: point.latitude,
                    longitude: point.longitude
                )
            }) ?? entry.workoutDetails?.originLocation
        else { return nil }
        return EntryDetailMapEndpoint(
            name: entry.workoutDetails?.originPlace?.name ?? "Origin",
            location: location,
            systemImage: entry.workoutDetails?.originPlace?.systemImage
                ?? .mappin
        )
    }

    private var workoutDestination: EntryDetailMapEndpoint? {
        guard entry.workoutDetails?.movementKind == .moving,
            let location = points.last.map({ point in
                Location(
                    latitude: point.latitude,
                    longitude: point.longitude
                )
            }) ?? entry.workoutDetails?.destinationLocation
        else {
            return nil
        }
        return EntryDetailMapEndpoint(
            name: entry.workoutDetails?.destinationPlace?.name
                ?? "Destination",
            location: location,
            systemImage: entry.workoutDetails?.destinationPlace?.systemImage
                ?? .mappin
        )
    }

    private var workoutPlace: EntryDetailMapEndpoint? {
        guard entry.workoutDetails?.movementKind != .moving,
            let location = entry.workoutDetails?.sourceLocation
                ?? entry.workoutDetails?.place?.location
        else { return nil }
        return EntryDetailMapEndpoint(
            name: entry.workoutDetails?.place?.name ?? "Workout location",
            location: location,
            systemImage: entry.workoutDetails?.place?.systemImage ?? .mappin
        )
    }
}

private struct EmptyMapContent: MapContent {
    var body: some MapContent {
        MapCircle(center: .init(), radius: 0).foregroundStyle(.clear)
    }
}

private struct EntryDetailMapEndpoint {
    let name: String
    let location: Location
    let systemImage: PlaceSystemImage
}

private struct EntryDetailMapMarker: MapContent {
    let endpoint: EntryDetailMapEndpoint

    var body: some MapContent {
        Marker(
            endpoint.name,
            systemImage: endpoint.systemImage.rawValue,
            coordinate: endpoint.location.coordinate
        )
        .tint(PlaceSymbols.symbol(for: endpoint.systemImage).primary)
    }
}

struct EntryDetailTimeCard: View {
    let startTime: Date?
    let endTime: Date?
    let startTimeZoneIdentifier: String
    let endTimeZoneIdentifier: String
    let editable: Bool
    let needsReview: Bool
    let onEdit: () -> Void

    var body: some View {
        Button(action: editable ? onEdit : {}) {
            VStack(alignment: .leading, spacing: 1) {
                EntryDetailDateText(
                    date: startTime,
                    timeZoneIdentifier: startTimeZoneIdentifier
                )
                EntryDetailDurationRow(duration: duration)
                EntryDetailDateText(
                    date: endTime,
                    timeZoneIdentifier: endTimeZoneIdentifier
                )
            }
            .padding(.leading, 10)
            .padding(.trailing, editable ? 30 : 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(maxHeight: .infinity)
        .background(.background, in: .rect(cornerRadius: 22))
        .overlay(alignment: .topTrailing) {
            if editable {
                EntryDetailChevron()
                    .padding(.top, 9)
                    .padding(.trailing, 12)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if needsReview {
                EntryDetailReviewBadge().padding(8)
            }
        }
    }

    private var duration: TimeInterval {
        guard let startTime, let endTime else { return 0 }
        return max(0, endTime.timeIntervalSince(startTime))
    }
}

private struct EntryDetailDateText: View {
    let date: Date?
    let timeZoneIdentifier: String

    var body: some View {
        if let date {
            Text(
                "\(date, format: .dateTime.hour().minute()), \(date, format: .dateTime.month(.wide)) \(date, format: .dateTime.day())"
            )
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .environment(
                \.timeZone,
                TimeZone(identifier: timeZoneIdentifier) ?? .current
            )
            .fontWeight(.medium)
        } else {
            Text("Needs review")
                .foregroundStyle(.secondary)
        }
    }
}

private struct EntryDetailDurationRow: View {
    let duration: TimeInterval

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 3) {
                ForEach(0..<3) { _ in
                    Capsule()
                        .fill(.tertiary)
                        .frame(width: 2, height: 8)
                }
            }
            Text(duration, format: .compactDuration)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
    }
}

struct EntryDetailTransitCard: View {
    let details: TransitDetails
    let needsReview: Bool
    let onEdit: () -> Void

    var body: some View {
        let presentation = TransitPresentationCatalog.presentation(
            for: details.type
        )
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 2) {
                if presentation.brandImage != nil {
                    TransitPresentationIcon(
                        presentation: presentation,
                        size: 42,
                        weight: .semibold
                    )
                } else {
                    TransitPresentationIcon(
                        presentation: presentation,
                        size: 23,
                        weight: .semibold
                    )
                    Text(details.type)
                        .font(.headline)
                        .lineLimit(1)
                }
                if let operatorName = details.sourceOrganizationName,
                    !operatorName.isEmpty
                {
                    Text(operatorName)
                        .font(.caption)
                        .foregroundStyle(
                            presentation.foregroundColor.opacity(0.75)
                        )
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(metadataText)
                    .font(.subheadline)
                    .foregroundStyle(presentation.foregroundColor.opacity(0.82))
                    .lineLimit(1)
            }
            .padding(.leading, 13)
            .padding(.trailing, 32)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: details.type))
        .accessibilityValue(Text(verbatim: metadataText))
        .foregroundStyle(presentation.foregroundColor)
        .frame(maxHeight: .infinity)
        .background(presentation.color, in: .rect(cornerRadius: 22))
        .overlay(alignment: .topTrailing) {
            EntryDetailChevron()
                .foregroundStyle(presentation.foregroundColor)
                .padding(.top, 11)
                .padding(.trailing, 12)
        }
        .overlay(alignment: .bottomTrailing) {
            if needsReview {
                EntryDetailReviewBadge().padding(8)
            }
        }
    }

    private var metadataText: String {
        var components: [String] = []
        if let identifier = details.sourceServiceIdentifier,
            !identifier.isEmpty
        {
            components.append(identifier)
        }
        if let distance = details.distanceMeters {
            components.append(
                Measurement(value: distance, unit: UnitLength.meters)
                    .formatted(.measurement(width: .abbreviated))
            )
        }
        return components.isEmpty
            ? String(localized: "Distance unavailable")
            : components.joined(separator: " • ")
    }
}

struct EntryDetailWorkoutCard: View {
    let details: WorkoutDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineFixedSymbol(
                systemName: WorkoutActivityCatalog.presentation(
                    for: details.activityTypeRawValue
                ).systemImageName,
                size: 23,
                weight: .semibold
            )
            Text(details.activityName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(metrics)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.black)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(
            maxWidth: .infinity,
            minHeight: 88,
            maxHeight: .infinity,
            alignment: .leading
        )
        .background(Color(hex: 0xB6FF00), in: .rect(cornerRadius: 22))
    }

    private var metrics: String {
        var values: [String] = []
        if let energy = details.activeEnergyKilocalories {
            values.append(
                energy.formatted(
                    .number.precision(.fractionLength(0))
                ) + "KCAL"
            )
        }
        if let distance = details.distanceMeters {
            values.append(
                Measurement(value: distance, unit: UnitLength.meters)
                    .formatted(.measurement(width: .abbreviated))
            )
        }
        return values.isEmpty
            ? String(localized: "Health workout")
            : values.joined(separator: " • ")
    }
}

struct EntryDetailWeatherCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let weather: EntryWeather?
    let location: Location?
    let placeSystemImage: PlaceSystemImage?
    let time: Date?
    let timeZoneIdentifier: String

    var body: some View {
        HStack(spacing: 7) {
            if let _ = weather {
                TimelineWeatherSymbol(
                    symbolName: weather?.symbolName ?? "cloud.slash.fill",
                    size: 27
                )
            }
            VStack(alignment: .leading, spacing: 0) {
                if let weather {
                    Text(
                        "\(weather.temperatureCelsius, format: .number.precision(.fractionLength(0)))°C"
                    )
                    .font(.title3.weight(.medium))
                    HStack(spacing: 3) {
                        TimelineFixedSymbol(
                            systemName: "humidity.fill",
                            size: 11
                        )
                        Text(
                            weather.humidity,
                            format: .percent.precision(.fractionLength(0))
                        )
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                } else {
                    Text("Weather unavailable")
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 1) {
                if let placeSystemImage {
                    EntryDetailWeatherPlaceSymbol(
                        systemImage: placeSystemImage,
                        size: 15
                    )
                }
                if let time {
                    Text(time, format: .dateTime.hour().minute())
                        .environment(
                            \.timeZone,
                            TimeZone(identifier: timeZoneIdentifier) ?? .current
                        )
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.88))
        }
        .foregroundStyle(.white)
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .padding(.vertical, 6)
        .frame(
            maxWidth: .infinity,
            minHeight: 44,
            maxHeight: .infinity,
            alignment: .leading
        )
        .background(weatherGradient, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var weatherGradient: LinearGradient {
        TimelineWeatherGradient.gradient(
            weather: weather,
            location: location.map {
                TimelineLocationSnapshot(
                    place: nil,
                    fallbackName: $0.preferredName ?? "Weather location",
                    fallbackLocation: $0
                )
            },
            timeZoneIdentifier: timeZoneIdentifier,
            colorScheme: colorScheme
        )
    }
}

private struct EntryDetailWeatherPlaceSymbol: View {
    let systemImage: PlaceSystemImage
    let size: CGFloat

    var body: some View {
        let symbol = PlaceSymbols.symbol(for: systemImage)
        Image(systemName: symbol.systemImage.rawValue)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.white.opacity(0.88))
            .frame(width: size, height: size)
    }
}

struct EntryDetailSectionButton: View {
    let title: LocalizedStringResource
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(title).font(.title3.bold())
                Spacer()
                EntryDetailChevron()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
    }
}

struct EntryDetailPhotoGrid: View {
    let references: [PhotoReference]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        if references.isEmpty {
            ContentUnavailableView(
                "No Photos",
                systemImage: "photo.on.rectangle"
            )
            .frame(maxWidth: .infinity, minHeight: 100)
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(references) { reference in
                    EntryDetailPhotoThumbnail(reference: reference)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 22))
                }
            }
        }
    }
}

struct EntryDetailPhotoThumbnail: View {
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
                Image(systemName: "photo.badge.exclamationmark")
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
                    width: 220 * displayScale,
                    height: 220 * displayScale
                )
            )
            didFinishLoading = true
        }
    }
}

struct EntryDetailChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct EntryDetailReviewBadge: View {
    var body: some View {
        Image(systemName: "exclamationmark")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(.orange, in: .circle)
            .accessibilityLabel("Needs review")
    }
}
