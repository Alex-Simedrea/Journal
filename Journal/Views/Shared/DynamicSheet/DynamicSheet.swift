//
//  DynamicSheet.swift
//  Journal
//

import SwiftUI
import UIKit

enum DynamicSheetSizing: Equatable {
    case content
    case expanded
}

struct DynamicSheet<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheetHeight: CGFloat = 0

    let animation: Animation
    let sizing: DynamicSheetSizing
    @ViewBuilder let content: Content

    init(
        animation: Animation = .snappy(duration: 0.25),
        sizing: DynamicSheetSizing = .content,
        @ViewBuilder content: () -> Content
    ) {
        self.animation = animation
        self.sizing = sizing
        self.content = content()
    }

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: sizing == .content)
            .frame(maxHeight: sizing == .expanded ? .infinity : nil)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                guard sizing == .content else { return }
                updateSheetHeight(newHeight)
            }
            .modifier(DynamicSheetHeight(height: sheetHeight))
            .presentationDragIndicator(.hidden)
            .presentationContentInteraction(.scrolls)
            .onChange(of: sizing) { _, newSizing in
                guard newSizing == .expanded else { return }
                updateSheetHeight(DynamicSheetWindowMetrics.expandedHeight)
            }
    }

    private func updateSheetHeight(_ newHeight: CGFloat) {
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
}

@Animatable
struct DynamicSheetHeight: ViewModifier {
    var height: CGFloat

    func body(content: Content) -> some View {
        content.presentationDetents(
            height > 0 ? [.height(height)] : [.medium]
        )
    }
}
