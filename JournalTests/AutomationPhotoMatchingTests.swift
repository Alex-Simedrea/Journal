import Foundation
import Testing

@testable import Journal

@Suite("Automatic photo matching")
struct AutomationPhotoMatchingTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Static matching includes time boundaries and respects radius")
    func staticMatching() {
        let target = AutomaticPhotoMatchTarget(
            entryID: UUID(),
            startTime: start,
            endTime: start.addingTimeInterval(600),
            geometry: .staticLocation(
                latitude: 44.4268,
                longitude: 26.1025,
                radiusMeters: 250
            )
        )

        #expect(PhotoAutoLinkService.matches(
            photo(at: start, latitude: 44.4268, longitude: 26.1025),
            target: target
        ))
        #expect(PhotoAutoLinkService.matches(
            photo(
                at: start.addingTimeInterval(600),
                latitude: 44.4268,
                longitude: 26.1025
            ),
            target: target
        ))
        #expect(!PhotoAutoLinkService.matches(
            photo(
                at: start.addingTimeInterval(300),
                latitude: 44.4368,
                longitude: 26.1025
            ),
            target: target
        ))
        #expect(!PhotoAutoLinkService.matches(
            photo(
                at: start.addingTimeInterval(-1),
                latitude: 44.4268,
                longitude: 26.1025
            ),
            target: target
        ))
    }

    @Test("Moving matching accepts the endpoint corridor and rejects detours")
    func corridorMatching() {
        let target = AutomaticPhotoMatchTarget(
            entryID: UUID(),
            startTime: start,
            endTime: start.addingTimeInterval(1_800),
            geometry: .corridor(
                originLatitude: 44.40,
                originLongitude: 26.00,
                destinationLatitude: 44.40,
                destinationLongitude: 26.14
            )
        )

        #expect(PhotoAutoLinkService.matches(
            photo(
                at: start.addingTimeInterval(600),
                latitude: 44.40,
                longitude: 26.07
            ),
            target: target
        ))
        #expect(!PhotoAutoLinkService.matches(
            photo(
                at: start.addingTimeInterval(600),
                latitude: 44.52,
                longitude: 26.07
            ),
            target: target
        ))
    }

    private func photo(
        at date: Date,
        latitude: Double,
        longitude: Double
    ) -> AutomaticPhotoMetadata {
        AutomaticPhotoMetadata(
            assetLocalIdentifier: UUID().uuidString,
            creationDate: date,
            latitude: latitude,
            longitude: longitude
        )
    }
}
