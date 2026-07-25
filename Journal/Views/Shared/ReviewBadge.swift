import SwiftUI

struct ReviewBadge: View {
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: "exclamationmark")
            .resizable()
            .scaledToFit()
            .fontWeight(.black)
            .foregroundStyle(.white)
            .frame(width: size * 3 / 17, height: size * 9 / 17)
            .frame(width: size, height: size)
            .background(.orange, in: .circle)
            .accessibilityLabel("Needs review")
    }
}
