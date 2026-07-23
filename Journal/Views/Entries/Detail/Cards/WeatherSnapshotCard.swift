import MapKit
import Photos
import SwiftUI

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
