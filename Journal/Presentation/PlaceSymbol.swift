//
//  PlaceSymbol.swift
//  Journal
//

import SwiftUI

struct PlaceSymbol: Identifiable {
    let systemImage: PlaceSystemImage
    let primary: Color
    let secondary: Color
    let tertiary: Color

    var id: PlaceSystemImage { systemImage }
}

enum PlaceSymbols {
    static let all = [
        PlaceSymbol(systemImage: .mappin, primary: .red, secondary: .pink, tertiary: .orange),
        PlaceSymbol(systemImage: .house, primary: .blue, secondary: .cyan, tertiary: .indigo),
        PlaceSymbol(systemImage: .buildings, primary: .indigo, secondary: .blue, tertiary: .gray),
        PlaceSymbol(systemImage: .civicBuilding, primary: .brown, secondary: .orange, tertiary: .yellow),
        PlaceSymbol(systemImage: .storefront, primary: .orange, secondary: .yellow, tertiary: .red),
        PlaceSymbol(systemImage: .cart, primary: .blue, secondary: .mint, tertiary: .cyan),
        PlaceSymbol(systemImage: .bag, primary: .pink, secondary: .purple, tertiary: .orange),
        PlaceSymbol(systemImage: .dining, primary: .orange, secondary: .red, tertiary: .yellow),
        PlaceSymbol(systemImage: .cafe, primary: .brown, secondary: .orange, tertiary: .mint),
        PlaceSymbol(systemImage: .bar, primary: .purple, secondary: .pink, tertiary: .red),
        PlaceSymbol(systemImage: .cake, primary: .pink, secondary: .orange, tertiary: .yellow),
        PlaceSymbol(systemImage: .hotel, primary: .indigo, secondary: .purple, tertiary: .blue),
        PlaceSymbol(systemImage: .medical, primary: .red, secondary: .pink, tertiary: .white),
        PlaceSymbol(systemImage: .pharmacy, primary: .pink, secondary: .cyan, tertiary: .white),
        PlaceSymbol(systemImage: .stethoscope, primary: .teal, secondary: .cyan, tertiary: .blue),
        PlaceSymbol(systemImage: .school, primary: .indigo, secondary: .purple, tertiary: .yellow),
        PlaceSymbol(systemImage: .library, primary: .blue, secondary: .cyan, tertiary: .orange),
        PlaceSymbol(systemImage: .work, primary: .brown, secondary: .orange, tertiary: .yellow),
        PlaceSymbol(systemImage: .computer, primary: .blue, secondary: .indigo, tertiary: .gray),
        PlaceSymbol(systemImage: .walking, primary: .green, secondary: .mint, tertiary: .cyan),
        PlaceSymbol(systemImage: .running, primary: .orange, secondary: .red, tertiary: .yellow),
        PlaceSymbol(systemImage: .gym, primary: .gray, secondary: .blue, tertiary: .indigo),
        PlaceSymbol(systemImage: .sports, primary: .green, secondary: .mint, tertiary: .white),
        PlaceSymbol(systemImage: .soccer, primary: .green, secondary: .gray, tertiary: .white),
        PlaceSymbol(systemImage: .basketball, primary: .orange, secondary: .brown, tertiary: .black),
        PlaceSymbol(systemImage: .nature, primary: .green, secondary: .mint, tertiary: .yellow),
        PlaceSymbol(systemImage: .park, primary: .green, secondary: .brown, tertiary: .mint),
        PlaceSymbol(systemImage: .mountain, primary: .gray, secondary: .green, tertiary: .cyan),
        PlaceSymbol(systemImage: .beach, primary: .cyan, secondary: .yellow, tertiary: .orange),
        PlaceSymbol(systemImage: .camping, primary: .orange, secondary: .green, tertiary: .brown),
        PlaceSymbol(systemImage: .water, primary: .cyan, secondary: .blue, tertiary: .teal),
        PlaceSymbol(systemImage: .airport, primary: .blue, secondary: .cyan, tertiary: .indigo),
        PlaceSymbol(systemImage: .car, primary: .blue, secondary: .cyan, tertiary: .gray),
        PlaceSymbol(systemImage: .bus, primary: .green, secondary: .mint, tertiary: .yellow),
        PlaceSymbol(systemImage: .tram, primary: .red, secondary: .orange, tertiary: .gray),
        PlaceSymbol(systemImage: .ferry, primary: .blue, secondary: .cyan, tertiary: .teal),
        PlaceSymbol(systemImage: .cycling, primary: .green, secondary: .mint, tertiary: .blue),
        PlaceSymbol(systemImage: .gasStation, primary: .red, secondary: .orange, tertiary: .gray),
        PlaceSymbol(systemImage: .parking, primary: .blue, secondary: .cyan, tertiary: .white),
        PlaceSymbol(systemImage: .camera, primary: .indigo, secondary: .purple, tertiary: .cyan),
        PlaceSymbol(systemImage: .music, primary: .purple, secondary: .pink, tertiary: .blue),
        PlaceSymbol(systemImage: .theater, primary: .purple, secondary: .pink, tertiary: .yellow),
        PlaceSymbol(systemImage: .ticket, primary: .orange, secondary: .yellow, tertiary: .pink),
        PlaceSymbol(systemImage: .gaming, primary: .indigo, secondary: .purple, tertiary: .cyan),
        PlaceSymbol(systemImage: .pets, primary: .brown, secondary: .orange, tertiary: .pink),
        PlaceSymbol(systemImage: .heart, primary: .red, secondary: .pink, tertiary: .orange),
        PlaceSymbol(systemImage: .star, primary: .yellow, secondary: .orange, tertiary: .pink),
        PlaceSymbol(systemImage: .people, primary: .blue, secondary: .cyan, tertiary: .indigo),
    ]

    static func symbol(for systemImage: PlaceSystemImage) -> PlaceSymbol {
        all.first { $0.systemImage == systemImage } ?? all[0]
    }
}
