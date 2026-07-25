import SwiftUI

struct FixedSizePlaceSymbol: View {
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
