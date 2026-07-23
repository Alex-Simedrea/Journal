import Foundation
import Observation

@MainActor
@Observable
final class BoardingPassImportCoordinator {
    var pendingImport: PendingBoardingPassImport?
    var errorMessage: String?

    func loadNextIfNeeded() {
        guard pendingImport == nil else { return }

        do {
            pendingImport = try BoardingPassImportInbox.oldest()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func complete(_ pendingImport: PendingBoardingPassImport) {
        remove(pendingImport)
    }

    func discard(_ pendingImport: PendingBoardingPassImport) {
        remove(pendingImport)
    }

    private func remove(_ completedImport: PendingBoardingPassImport) {
        do {
            try BoardingPassImportInbox.remove(id: completedImport.id)
            pendingImport = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
