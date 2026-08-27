import Combine
import Foundation

extension Notification.Name {
    static let timelineDataDidChange = Notification.Name(
        "journal.timelineDataDidChange"
    )
}

@MainActor
enum TimelineDataChange {
    enum Kind: Sendable {
        case enrichment
        case structure
    }

    static let publisher = Publishers.Merge(
        NotificationCenter.default.publisher(
            for: .timelineDataDidChange
        ).map { notification in
            notification.object as? Kind ?? .enrichment
        },
        NotificationCenter.default.publisher(
            for: .automationCandidatesDidChange
        ).map { _ in Kind.structure }
    )
    .receive(on: RunLoop.main)
    .debounce(for: .milliseconds(75), scheduler: RunLoop.main)
    .eraseToAnyPublisher()

    static func post(_ kind: Kind = .enrichment) {
        NotificationCenter.default.post(
            name: .timelineDataDidChange,
            object: kind
        )
    }
}
