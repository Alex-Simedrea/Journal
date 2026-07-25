import SwiftUI

struct FixedSizeSymbol: View {
    let systemName: String
    let size: CGFloat
    var weight: Font.Weight = .regular

    var body: some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .fontWeight(weight)
            .frame(width: size, height: size)
    }
}
