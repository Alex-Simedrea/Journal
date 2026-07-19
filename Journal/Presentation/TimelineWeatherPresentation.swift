//
//  TimelineWeatherPresentation.swift
//  Journal
//

import Foundation

enum TimelineWeatherSkyPhase: Equatable, Sendable {
    case dawn
    case day
    case dusk
    case night
}

enum TimelineWeatherConditionFamily: Equatable, Sendable {
    case clear
    case cloud
    case rain
    case snow
    case storm
    case wind
}

enum TimelineWeatherPresentation {
    static func skyPhase(
        date: Date,
        latitude: Double?,
        longitude: Double?,
        symbolName: String,
        timeZone: TimeZone
    ) -> TimelineWeatherSkyPhase {
        if let latitude,
           let longitude,
           (-90...90).contains(latitude),
           (-180...180).contains(longitude) {
            let position = solarPosition(
                date: date,
                latitude: latitude,
                longitude: longitude
            )
            if position.elevationDegrees > 3 {
                return .day
            }
            if position.elevationDegrees < -6 {
                return .night
            }
            return position.hourAngleDegrees < 0 ? .dawn : .dusk
        }

        if symbolName.contains("moon") {
            return .night
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        switch calendar.component(.hour, from: date) {
        case 5..<7: return .dawn
        case 7..<18: return .day
        case 18..<20: return .dusk
        default: return .night
        }
    }

    static func conditionFamily(
        symbolName: String
    ) -> TimelineWeatherConditionFamily {
        if symbolName.contains("bolt") || symbolName.contains("storm") {
            return .storm
        }
        if symbolName.contains("snow") || symbolName.contains("sleet") {
            return .snow
        }
        if symbolName.contains("rain") || symbolName.contains("drizzle") {
            return .rain
        }
        if symbolName.contains("wind") {
            return .wind
        }
        if symbolName.contains("cloud") || symbolName.contains("fog") {
            return .cloud
        }
        return .clear
    }

    static func gradientHexes(
        symbolName: String,
        phase: TimelineWeatherSkyPhase
    ) -> [UInt32] {
        let family = conditionFamily(symbolName: symbolName)
        switch phase {
        case .dawn:
            return switch family {
            case .storm: [0x41446F, 0x7D6684, 0xD89878]
            case .rain: [0x425B83, 0x7189A5, 0xD5A17F]
            case .snow: [0x718BA5, 0xB7C8D5, 0xF2C5A0]
            case .cloud: [0x596A8D, 0x93A0B1, 0xDDA581]
            case .wind: [0x3E777D, 0x76A5A3, 0xE0AC87]
            case .clear: [0x4D5F9B, 0xB77791, 0xF0AA76]
            }
        case .day:
            return switch family {
            case .storm: [0x41466F, 0x8173A8]
            case .rain: [0x3D6B9B, 0x91B5D1]
            case .snow: [0x62A7C5, 0xD5EFF5]
            case .cloud: [0x6683A2, 0xB8C8D6]
            case .wind: [0x31958F, 0x98D4CF]
            case .clear: [0x259FDF, 0xA8DFFF]
            }
        case .dusk:
            return switch family {
            case .storm: [0x313B68, 0x76557A, 0xB85E68]
            case .rain: [0x354D73, 0x667A98, 0xB46E72]
            case .snow: [0x627A99, 0xA6B5C7, 0xD99086]
            case .cloud: [0x465878, 0x7F879B, 0xC87975]
            case .wind: [0x336D72, 0x668F90, 0xC87E72]
            case .clear: [0x374A83, 0x8D5C83, 0xD77368]
            }
        case .night:
            return switch family {
            case .storm: [0x1B2143, 0x4E486D]
            case .rain: [0x193551, 0x526E8C]
            case .snow: [0x35566E, 0x809BAD]
            case .cloud: [0x2D4058, 0x687D91]
            case .wind: [0x214E55, 0x5F8588]
            case .clear: [0x1E365C, 0x58749A]
            }
        }
    }

    private static func solarPosition(
        date: Date,
        latitude: Double,
        longitude: Double
    ) -> (elevationDegrees: Double, hourAngleDegrees: Double) {
        let julianDate = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let daysSinceJ2000 = julianDate - 2_451_545
        let meanLongitude = normalizedDegrees(
            280.46 + 0.985_647_4 * daysSinceJ2000
        )
        let meanAnomaly = degreesToRadians(
            normalizedDegrees(357.528 + 0.985_600_3 * daysSinceJ2000)
        )
        let eclipticLongitude = degreesToRadians(
            normalizedDegrees(
                meanLongitude
                    + 1.915 * sin(meanAnomaly)
                    + 0.020 * sin(2 * meanAnomaly)
            )
        )
        let obliquity = degreesToRadians(23.439 - 0.000_000_4 * daysSinceJ2000)
        let rightAscension = atan2(
            cos(obliquity) * sin(eclipticLongitude),
            cos(eclipticLongitude)
        )
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))
        let greenwichSiderealHours = normalizedHours(
            18.697_374_558 + 24.065_709_824_419_08 * daysSinceJ2000
        )
        let localSiderealDegrees = (greenwichSiderealHours + longitude / 15) * 15
        let hourAngle = normalizedSignedDegrees(
            localSiderealDegrees - radiansToDegrees(rightAscension)
        )
        let latitudeRadians = degreesToRadians(latitude)
        let elevation = asin(
            sin(latitudeRadians) * sin(declination)
                + cos(latitudeRadians) * cos(declination)
                    * cos(degreesToRadians(hourAngle))
        )
        return (radiansToDegrees(elevation), hourAngle)
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private static func normalizedSignedDegrees(_ value: Double) -> Double {
        let normalized = normalizedDegrees(value)
        return normalized > 180 ? normalized - 360 : normalized
    }

    private static func normalizedHours(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 24)
        return remainder >= 0 ? remainder : remainder + 24
    }

    private static func degreesToRadians(_ value: Double) -> Double {
        value * .pi / 180
    }

    private static func radiansToDegrees(_ value: Double) -> Double {
        value * 180 / .pi
    }
}
