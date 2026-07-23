import SwiftUI
import UIKit

enum DynamicSheetWindowMetrics {
    private static let expandedTopGap: CGFloat = 16

    static var expandedHeight: CGFloat {
        guard let scene = activeScene else { return 884 }
        let windowHeight = scene.keyWindow?.bounds.height
            ?? scene.screen.bounds.height
        let safeAreaInsets = scene.keyWindow?.safeAreaInsets ?? .zero
        return max(
            1,
            windowHeight
                - safeAreaInsets.top
                - safeAreaInsets.bottom
                - expandedTopGap
        )
    }

    static var availableHeight: CGFloat {
        guard let scene = activeScene else {
            return 700
        }
        let insets = scene.keyWindow?.safeAreaInsets ?? .zero
        return scene.screen.bounds.height - insets.top - insets.bottom
    }

    private static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
    }
}

extension UIWindowScene {
    fileprivate var keyWindow: UIWindow? {
        windows.first(where: \.isKeyWindow)
    }
}
