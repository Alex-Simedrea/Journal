//
//  PlaceSymbolPicker.swift
//  Journal
//

import SwiftUI

struct PlaceSymbolPicker: View {
    @Binding var selection: PlaceSystemImage

    var body: some View {
        ScrollView {
            PlaceSymbolGrid(selection: $selection)
        }
        .navigationTitle("Symbol")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PlaceSymbolGrid: View {
    @Binding var selection: PlaceSystemImage

    private let columns = [
        GridItem(.adaptive(minimum: 56), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(PlaceSymbols.all) { symbol in
                Button {
                    selection = symbol.systemImage
                } label: {
                    PlaceSymbolImage(systemImage: symbol.systemImage)
                        .font(.title2)
                        .frame(width: 52, height: 52)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    selection == symbol.systemImage
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.secondary.opacity(0.08)
                                )
                        }
                        .overlay(alignment: .topTrailing) {
                            if selection == symbol.systemImage {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.white, .tint)
                                    .offset(x: 4, y: -4)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol.systemImage.rawValue)
                .accessibilityAddTraits(
                    selection == symbol.systemImage ? .isSelected : []
                )
            }
        }
        .padding()
    }
}

struct PlaceSymbolImage: View {
    let systemImage: PlaceSystemImage

    private var symbol: PlaceSymbol {
        PlaceSymbols.symbol(for: systemImage)
    }

    var body: some View {
        Image(systemName: symbol.systemImage.rawValue)
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                symbol.primary.gradient,
                symbol.secondary.gradient,
                symbol.tertiary.gradient
            )
    }
}
