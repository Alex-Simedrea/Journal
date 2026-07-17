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
        removeAndAdvance(pendingImport)
    }

    func discard(_ pendingImport: PendingBoardingPassImport) {
        removeAndAdvance(pendingImport)
    }

    func deferCurrentImport() {
        pendingImport = nil
    }

    private func removeAndAdvance(
        _ completedImport: PendingBoardingPassImport
    ) {
        do {
            try BoardingPassImportInbox.remove(id: completedImport.id)
            pendingImport = nil
            Task {
                await Task.yield()
                loadNextIfNeeded()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
