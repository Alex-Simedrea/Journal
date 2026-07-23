import SwiftUI
import UIKit

struct DynamicSheetScrollView<Content: View>: View {
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @Binding private var isScrolled: Bool
    let fillsAvailableHeight: Bool
    let indexItems: [DynamicSheetScrollIndexItem]
    let topContentInset: CGFloat
    @ViewBuilder let content: Content

    init(
        fillsAvailableHeight: Bool = false,
        indexItems: [DynamicSheetScrollIndexItem] = [],
        topContentInset: CGFloat = 0,
        isScrolled: Binding<Bool> = .constant(false),
        @ViewBuilder content: () -> Content
    ) {
        self.fillsAvailableHeight = fillsAvailableHeight
        self.indexItems = indexItems
        self.topContentInset = topContentInset
        _isScrolled = isScrolled
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    content

                    if !indexItems.isEmpty {
                        Color.clear
                            .frame(height: indexTrailingScrollRange)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: {
                    guard !fillsAvailableHeight else { return }
                    contentHeight = $0
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(
                .top,
                topContentInset,
                for: .scrollContent
            )
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 0.5
            } action: { _, newValue in
                if isScrolled != newValue {
                    isScrolled = newValue
                }
            }
            .scrollDisabled(
                !fillsAvailableHeight
                    && fittedContentHeight <= maximumViewportHeight
            )
            .frame(
                height: fillsAvailableHeight || contentHeight == 0
                    ? nil
                    : min(fittedContentHeight, maximumViewportHeight)
            )
            .frame(maxHeight: fillsAvailableHeight ? .infinity : nil)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { newHeight in
                guard abs(newHeight - viewportHeight) > 0.5 else {
                    return
                }
                viewportHeight = newHeight
            }
            .overlay {
                if !indexItems.isEmpty {
                    GeometryReader { geometry in
                        DynamicSheetScrollIndex(
                            items: indexItems,
                            availableHeight: geometry.size.height
                        ) { itemID in
                            proxy.scrollTo(itemID, anchor: .top)
                        }
                        .position(
                            x: geometry.size.width - 10,
                            y: geometry.size.height / 2
                        )
                    }
                }
            }
        }
    }

    private var maximumViewportHeight: CGFloat {
        max(260, DynamicSheetWindowMetrics.availableHeight - 130)
    }

    private var fittedContentHeight: CGFloat {
        contentHeight + topContentInset
    }

    private var indexTrailingScrollRange: CGFloat {
        max(0, viewportHeight - topContentInset)
    }
}
