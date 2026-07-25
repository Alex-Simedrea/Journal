import SwiftUI

struct DynamicSheetNavigationContainer<
    Route: Hashable,
    Content: View,
    Leading: View,
    Trailing: View,
    Accessory: View
>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let route: Route
    let movesForward: Bool
    let title: LocalizedStringResource
    let isScrolled: Bool
    @Binding var chromeHeight: CGFloat
    @ViewBuilder let content: Content
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let accessory: Accessory

    init(
        route: Route,
        movesForward: Bool,
        title: LocalizedStringResource,
        isScrolled: Bool,
        chromeHeight: Binding<CGFloat>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.route = route
        self.movesForward = movesForward
        self.title = title
        self.isScrolled = isScrolled
        _chromeHeight = chromeHeight
        self.content = content()
        self.leading = leading()
        self.trailing = trailing()
        self.accessory = accessory()
    }

    var body: some View {
        ZStack(alignment: .top) {
            content
                .id(route)
                .transition(
                    .blurReplace(movesForward ? .upUp : .downUp)
                )

            VStack(spacing: 0) {
                DynamicSheetHeader(
                    title: title,
                    isElevated: isScrolled,
                    leading: { leading },
                    trailing: { trailing }
                )

                accessory
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: {
                chromeHeight = $0
            }
        }
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.25),
            value: route
        )
        .sensoryFeedback(
            .impact(flexibility: .soft, intensity: 1),
            trigger: route
        )
    }
}
