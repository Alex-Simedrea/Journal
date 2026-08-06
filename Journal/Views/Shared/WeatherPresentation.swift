import SwiftUI

struct WeatherSymbol: View {
    let symbolName: String
    let size: CGFloat

    var body: some View {
        let palette = WeatherSymbolPalette.colors(for: symbolName)
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
            .frame(width: size, height: size, alignment: .top)
    }
}

enum WeatherSymbolPalette {
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

enum WeatherGradient {
    static func gradient(
        weather: EntryWeather?,
        latitude: Double?,
        longitude: Double?,
        timeZoneIdentifier: String,
        colorScheme: ColorScheme,
        presentationDate: Date? = nil
    ) -> LinearGradient {
        let symbolName = weather?.symbolName
            ?? (presentationDate == nil ? "cloud.slash.fill" : "sun.max.fill")
        let phase = WeatherPresentation.skyPhase(
            date: weather?.date ?? presentationDate ?? .now,
            latitude: latitude,
            longitude: longitude,
            symbolName: symbolName,
            timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current
        )
        let colors = WeatherPresentation.gradientHexes(
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
