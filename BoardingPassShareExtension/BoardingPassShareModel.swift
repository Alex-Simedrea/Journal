import Foundation
import Observation

enum BoardingPassSharePhase: Equatable {
    case loading
    case ready(PendingBoardingPassImport)
    case saving(PendingBoardingPassImport)
    case failed(String)
}

@MainActor
@Observable
final class BoardingPassShareModel {
    var phase: BoardingPassSharePhase = .loading

    func load(from extensionItems: [NSExtensionItem]) async {
        phase = .loading

        do {
            let provider = try boardingPassProvider(in: extensionItems)
            let data = try await loadBoardingPassData(from: provider)
            phase = .ready(try BoardingPassImporter.parse(data: data))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func storePendingImport() -> Bool {
        guard case .ready(let pendingImport) = phase else { return false }
        phase = .saving(pendingImport)

        do {
            try BoardingPassImportInbox.store(pendingImport)
            return true
        } catch {
            phase = .failed(error.localizedDescription)
            return false
        }
    }

    private func boardingPassProvider(
        in extensionItems: [NSExtensionItem]
    ) throws -> NSItemProvider {
        let providers = extensionItems.flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(
                JournalImportConfiguration.boardingPassTypeIdentifier
            )
        }) else {
            throw BoardingPassImportError.noBoardingPassAttachment
        }
        return provider
    }

    private func loadBoardingPassData(
        from provider: NSItemProvider
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(
                forTypeIdentifier: JournalImportConfiguration
                    .boardingPassTypeIdentifier
            ) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(
                        throwing: BoardingPassImportError.noBoardingPassAttachment
                    )
                    return
                }

                do {
                    continuation.resume(returning: try Data(contentsOf: url))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
