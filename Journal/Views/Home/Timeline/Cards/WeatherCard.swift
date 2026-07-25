import MapKit
import Photos
import SwiftUI

enum TimelineWeatherTileLayout {
    case compact
    case large
}

struct TimelineWeatherTile: View {
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
            WeatherGradient.gradient(
                weather: weather,
                latitude: location?.latitude,
                longitude: location?.longitude,
                timeZoneIdentifier: timeZoneIdentifier,
                colorScheme: colorScheme
            ),
            in: .rect(cornerRadius: 16)
        )
        .accessibilityElement(children: .combine)
    }
}

struct TimelineCompactWeatherContent: View {
    let weather: EntryWeather

    var body: some View {
        HStack(spacing: 7) {
            WeatherSymbol(symbolName: weather.symbolName, size: 26)

            VStack(alignment: .leading, spacing: 0) {
                TimelineTemperatureLabel(celsius: weather.temperatureCelsius)
                    .font(.title2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                TimelineHumidityLabel(humidity: weather.humidity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct TimelineLargeWeatherContent: View {
    let weather: EntryWeather

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WeatherSymbol(symbolName: weather.symbolName, size: 32)

            Spacer(minLength: 2)

            TimelineTemperatureLabel(celsius: weather.temperatureCelsius)
                .font(.title.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            TimelineHumidityLabel(humidity: weather.humidity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct TimelineTemperatureLabel: View {
    let celsius: Double

    var body: some View {
        Text(
            "\(celsius, format: .number.precision(.fractionLength(0)))°C"
        )
    }
}

struct TimelineHumidityLabel: View {
    let humidity: Double

    var body: some View {
        HStack(spacing: 3) {
            FixedSizeSymbol(systemName: "humidity.fill", size: 13)
            Text(humidity, format: .percent.precision(.fractionLength(0)))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white.opacity(0.8))
        .lineLimit(1)
    }
}

struct TimelineUnavailableWeatherContent: View {
    let layout: TimelineWeatherTileLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            FixedSizeSymbol(
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
