import Foundation
import Observation
import UniformTypeIdentifiers

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
            if let provider = boardingPassProvider(in: extensionItems) {
                let data = try await loadBoardingPassData(from: provider)
                phase = .ready(try BoardingPassImporter.parse(data: data))
            } else {
                phase = .ready(
                    try await loadFlightSummary(from: extensionItems)
                )
            }
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
    ) -> NSItemProvider? {
        let providers = extensionItems.flatMap { $0.attachments ?? [] }
        return providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(
                JournalImportConfiguration.boardingPassTypeIdentifier
            )
        })
    }

    private func textProviders(
        in extensionItems: [NSExtensionItem]
    ) -> [NSItemProvider] {
        extensionItems.flatMap { $0.attachments ?? [] }.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.text.identifier)
        }
    }

    private func attributedTexts(
        in extensionItems: [NSExtensionItem]
    ) -> [String] {
        extensionItems
            .compactMap(\.attributedContentText?.string)
            .filter { !$0.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty }
    }

    private func loadFlightSummary(
        from extensionItems: [NSExtensionItem]
    ) async throws -> PendingBoardingPassImport {
        var candidates = attributedTexts(in: extensionItems)
        var lastError: (any Error)?

        for provider in textProviders(in: extensionItems) {
            do {
                candidates.append(
                    try await SharedPlainTextLoader.load(from: provider)
                )
            } catch {
                lastError = error
            }
        }

        var triedCandidates = Set<String>()
        for candidate in candidates where triedCandidates.insert(candidate).inserted {
            do {
                return try BoardingPassImporter.parse(flightSummary: candidate)
            } catch {
                lastError = error
            }
        }

        if let lastError { throw lastError }
        throw BoardingPassImportError.noBoardingPassAttachment
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
