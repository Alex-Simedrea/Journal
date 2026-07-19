//
//  TransitPresentation.swift
//  Journal
//

import SwiftUI

struct TransitPresentation {
    let systemImageName: String
    let color: Color
    let foregroundColor: Color
}

enum TransitPresentationCatalog {
    static func presentation(for name: String) -> TransitPresentation {
        switch normalized(name) {
        case "walk": item("figure.walk", 0x34C759)
        case "bicycle": item("bicycle", 0x00C7BE)
        case "scooter": item("scooter", 0x32ADE6)
        case "motorcycle": item("motorcycle.fill", 0xFF9F0A)
        case "car": item("car.fill", 0x0A84FF)
        case "taxi": item("car.side.fill", 0xFFD60A, foreground: .black)
        case "ride share": item("person.2.fill", 0x5E5CE6)
        case "uber": item("car.fill", 0x000000)
        case "bolt": item("car.fill", 0x34BB78)
        case "lyft": item("car.fill", 0xFF00BF)
        case "bus": item("bus.fill", 0x30D158)
        case "train": item("train.side.front.car", 0xAF52DE)
        case "metro": item("tram.fill.tunnel", 0xFF453A)
        case "tram": item("tram.fill", 0xFF9F0A)
        case "ferry": item("ferry.fill", 0x64D2FF, foreground: .black)
        case "flight": item("airplane", 0x007AFF)
        default: item("arrow.triangle.swap", 0x6B7280)
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func item(
        _ systemImageName: String,
        _ hex: UInt32,
        foreground: Color = .white
    ) -> TransitPresentation {
        TransitPresentation(
            systemImageName: systemImageName,
            color: Color(hex: hex),
            foregroundColor: foreground
        )
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: opacity
        )
    }
}
