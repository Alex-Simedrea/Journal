import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private let model = BoardingPassShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(
            rootView: ShareBoardingPassView(
                model: model,
                onCancel: { [weak self] in self?.cancel() },
                onImport: { [weak self] in self?.saveAndComplete() }
            )
        )
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)

        Task {
            await model.load(from: extensionContext?.inputItems.compactMap {
                $0 as? NSExtensionItem
            } ?? [])
        }
    }

    private func saveAndComplete() {
        guard model.storePendingImport() else { return }

        ContainingAppOpener.open(
            BoardingPassImportDeepLink.url,
            from: self,
            extensionContext: extensionContext
        ) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func cancel() {
        let error = NSError(
            domain: "BoardingPassShareExtension",
            code: NSUserCancelledError,
            userInfo: nil
        )
        extensionContext?.cancelRequest(withError: error)
    }
}
