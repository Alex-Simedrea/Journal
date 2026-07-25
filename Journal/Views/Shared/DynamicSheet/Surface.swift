import SwiftUI

private struct DynamicSheetSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background(
            .white.opacity(colorScheme == .dark ? 0.1 : 0.5),
            in: .rect(cornerRadius: 24)
        )
    }
}

extension View {
    func dynamicSheetSurface() -> some View {
        modifier(DynamicSheetSurfaceModifier())
    }
}
