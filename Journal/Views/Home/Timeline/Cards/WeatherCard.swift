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

struct TimelineCompactWeatherContent: View {
    let weather: EntryWeather

    var body: some View {
        HStack(spacing: 7) {
            TimelineWeatherSymbol(symbolName: weather.symbolName, size: 26)

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
            TimelineWeatherSymbol(symbolName: weather.symbolName, size: 32)

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
            TimelineFixedSymbol(systemName: "humidity.fill", size: 13)
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

struct TimelineWeatherSymbol: View {
    let symbolName: String
    let size: CGFloat

    var body: some View {
        let palette = TimelineWeatherSymbolPalette.colors(for: symbolName)
        Image(systemName: symbolName)
            .resizable()
            .scaledToFit()
            .symbolVariant(.fill)
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                palette.primary,
                palette.secondary,
                palette.tertiary
            )
            .fontWeight(.semibold)
            .frame(width: size, height: size)
    }
}

enum TimelineWeatherSymbolPalette {
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

enum TimelineWeatherGradient {
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

struct TimelineFixedSymbol: View {
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

struct TimelineFixedPlaceSymbol: View {
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
