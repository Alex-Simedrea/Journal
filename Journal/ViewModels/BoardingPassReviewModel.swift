import Foundation
import Observation
import SwiftData

enum BoardingPassEndpoint: String, Identifiable {
    case origin
    case destination

    var id: String { rawValue }
}

@MainActor
@Observable
final class BoardingPassReviewModel {
    let pendingImport: PendingBoardingPassImport

    var transitType: String
    var originPlaceID: UUID?
    var destinationPlaceID: UUID?
    var originName: String
    var destinationName: String
    var startTime: Date
    var endTime: Date
    var placeBeingAdded: BoardingPassEndpoint?
    var isSaving = false
    var errorMessage: String?

    private let hadCompleteTime: Bool

    init(pendingImport: PendingBoardingPassImport) {
        self.pendingImport = pendingImport
        transitType = pendingImport.transitTypeName ?? ""
        originName = pendingImport.originName ?? ""
        destinationName = pendingImport.destinationName ?? ""

        let fallbackStart = pendingImport.startTime ?? .now
        startTime = fallbackStart
        endTime = max(
            pendingImport.endTime ?? fallbackStart.addingTimeInterval(60 * 60),
            fallbackStart.addingTimeInterval(60)
        )
        hadCompleteTime = pendingImport.startTime != nil
            && pendingImport.endTime != nil
    }

    var canSave: Bool {
        !transitType.isEmpty
            && !originName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !destinationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && endTime > startTime
            && !isSaving
    }

    func prepare(places: [Place], transitTypes: [TransitType]) {
        if transitType.isEmpty {
            transitType = transitTypes.first?.canonicalName ?? ""
        }
        if originPlaceID == nil {
            originPlaceID = matchPlace(named: originName, in: places)?.id
        }
        if destinationPlaceID == nil {
            destinationPlaceID = matchPlace(named: destinationName, in: places)?.id
        }
    }

    func beginAddingPlace(for endpoint: BoardingPassEndpoint) {
        placeBeingAdded = endpoint
    }

    func didAddPlace(_ place: Place, for endpoint: BoardingPassEndpoint) {
        switch endpoint {
        case .origin:
            originPlaceID = place.id
        case .destination:
            destinationPlaceID = place.id
        }
        placeBeingAdded = nil
    }

    func name(for endpoint: BoardingPassEndpoint) -> String {
        switch endpoint {
        case .origin: originName
        case .destination: destinationName
        }
    }

    func timeZoneIdentifier(
        for endpoint: BoardingPassEndpoint,
        places: [Place]
    ) -> String {
        let placeID = endpoint == .origin ? originPlaceID : destinationPlaceID
        return places.first(where: { $0.id == placeID })?
            .location.timeZoneIdentifier ?? TimeZone.current.identifier
    }

    func save(
        places: [Place],
        in modelContext: ModelContext
    ) async -> Bool {
        guard canSave else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let origin = places.first { $0.id == originPlaceID }
        let destination = places.first { $0.id == destinationPlaceID }
        var fieldReviews: [TransitFieldReview] = []
        if origin == nil {
            fieldReviews.append(
                TransitFieldReview(
                    field: .origin,
                    reason: "Link the boarding-pass origin to a saved place."
                )
            )
        }
        if destination == nil {
            fieldReviews.append(
                TransitFieldReview(
                    field: .destination,
                    reason: "Link the boarding-pass destination to a saved place."
                )
            )
        }

        let draft = ResolvedTransitDraft(
            transitType: transitType,
            originPlace: origin,
            originRawText: originName,
            destinationPlace: destination,
            destinationRawText: destinationName,
            startTime: startTime,
            endTime: endTime,
            timeConfidence: hadCompleteTime ? .explicit : .manualOverride,
            people: [],
            durationSource: hadCompleteTime ? .unresolved : .manualOverride,
            originCandidates: [],
            destinationCandidates: [],
            unresolvedPeople: [],
            fieldReviews: fieldReviews
        )
        let issuer = pendingImport.organizationName

        do {
            let entry = try TransitEntryStore.insert(
                draft: draft,
                rawInput: nil,
                sourceOrganizationName: issuer,
                sourceServiceIdentifier: pendingImport.serviceIdentifier,
                in: modelContext
            )
            _ = try? await EntryWeatherService.populate(
                entry,
                in: modelContext
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func matchPlace(named name: String, in places: [Place]) -> Place? {
        let normalizedName = normalize(name)
        guard !normalizedName.isEmpty else { return nil }

        let exactNames = places.filter { normalize($0.name) == normalizedName }
        if exactNames.count == 1 {
            return exactNames[0]
        }
        let aliasMatches = places.filter { place in
            place.aliases.contains { normalize($0) == normalizedName }
        }
        return aliasMatches.count == 1 ? aliasMatches[0] : nil
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
