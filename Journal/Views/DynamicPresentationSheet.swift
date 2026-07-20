//
//  DynamicPresentationSheet.swift
//  Journal
//

import SwiftUI
import UIKit

struct DynamicPresentationSheet<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheetHeight: CGFloat = 0

    let animation: Animation
    @ViewBuilder let content: Content

    init(
        animation: Animation = .snappy(duration: 0.25),
        @ViewBuilder content: () -> Content
    ) {
        self.animation = animation
        self.content = content()
    }

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                guard newHeight > 0, abs(newHeight - sheetHeight) > 0.5 else {
                    return
                }
                if sheetHeight == 0 || reduceMotion {
                    sheetHeight = newHeight
                } else {
                    withAnimation(animation) {
                        sheetHeight = newHeight
                    }
                }
            }
            .modifier(DynamicPresentationHeight(height: sheetHeight))
            .presentationDragIndicator(.hidden)
            .presentationContentInteraction(.scrolls)
    }
}

private struct DynamicPresentationHeight: ViewModifier, Animatable {
    var height: CGFloat

    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    func body(content: Content) -> some View {
        content.presentationDetents(
            height > 0 ? [.height(height)] : [.medium]
        )
    }
}

struct DynamicSheetScrollView<Content: View>: View {
    @State private var contentHeight: CGFloat = 0
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { contentHeight = $0 }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .scrollDisabled(contentHeight <= maximumViewportHeight)
        .frame(
            height: contentHeight == 0
                ? nil
                : min(contentHeight, maximumViewportHeight)
        )
    }

    private var maximumViewportHeight: CGFloat {
        max(260, EntrySheetWindowMetrics.availableHeight - 130)
    }
}

private enum EntrySheetWindowMetrics {
    static var availableHeight: CGFloat {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first else {
            return 700
        }
        let insets = scene.keyWindow?.safeAreaInsets ?? .zero
        return scene.screen.bounds.height - insets.top - insets.bottom
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first(where: \.isKeyWindow)
    }
}
