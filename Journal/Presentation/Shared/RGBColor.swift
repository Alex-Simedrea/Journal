import SwiftUI

struct RGBColor: Equatable, Sendable {
    let red: Int
    let green: Int
    let blue: Int

    var color: Color {
        Color(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
    }
}
