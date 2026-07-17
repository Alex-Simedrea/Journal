import UIKit

enum ContainingAppOpener {
    private static let containingAppBundleIdentifier =
        "ro.attractivestar.Journal"

    static func open(
        _ url: URL,
        from responder: UIResponder,
        extensionContext: NSExtensionContext?,
        completion: @escaping () -> Void
    ) {
        _ = responder
        _ = extensionContext

        JournalOpenContainingApplication(
            url,
            containingAppBundleIdentifier
        )

        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(300),
            execute: completion
        )
    }
}
