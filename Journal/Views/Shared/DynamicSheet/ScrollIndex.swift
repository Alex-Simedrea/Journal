import SwiftUI
import UIKit

struct DynamicSheetScrollIndexItem: Identifiable, Equatable {
    let id: String
    let title: String?
    let systemImage: String?

    init(id: String, title: String) {
        self.id = id
        self.title = title
        systemImage = nil
    }

    init(id: String, systemImage: String) {
        self.id = id
        title = nil
        self.systemImage = systemImage
    }
}

struct DynamicSheetScrollIndex: View {
    let items: [DynamicSheetScrollIndexItem]
    let availableHeight: CGFloat
    let onSelect: (String) -> Void

    @State private var indexHeight: CGFloat = 0
    @State private var activeItemID: String?
    @State private var hapticTrigger = 0

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    activeItemID = nil
                    select(item.id)
                } label: {
                    if let systemImage = item.systemImage {
                        Image(systemName: systemImage)
                    } else if let title = item.title {
                        Text(title)
                    }
                }
                .font(.system(size: min(10, rowHeight), weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 20, height: rowHeight)
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: item))
            }
        }
        .padding(.vertical, 6)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: {
            indexHeight = $0
        }
        .contentShape(.rect)
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    selectItem(at: value.location.y)
                }
                .onEnded { _ in
                    activeItemID = nil
                }
        )
        .sensoryFeedback(.selection, trigger: hapticTrigger)
    }

    private var rowHeight: CGFloat {
        guard !items.isEmpty else { return 14 }
        return min(14, max(7, (availableHeight - 12) / CGFloat(items.count)))
    }

    private func selectItem(at locationY: CGFloat) {
        guard !items.isEmpty, indexHeight > 12 else { return }
        let availableIndexHeight = indexHeight - 12
        let position = min(
            max(locationY - 6, 0),
            max(availableIndexHeight.nextDown, 0)
        )
        let index = min(
            items.count - 1,
            Int(position / availableIndexHeight * CGFloat(items.count))
        )
        select(items[index].id)
    }

    private func select(_ itemID: String) {
        guard activeItemID != itemID else { return }
        activeItemID = itemID
        hapticTrigger += 1
        onSelect(itemID)
    }

    private func accessibilityLabel(
        for item: DynamicSheetScrollIndexItem
    ) -> String {
        if item.systemImage == "star.fill" {
            return String(localized: "Jump to Most Used")
        }
        return String(localized: "Jump to \(item.title ?? item.id)")
    }
}
