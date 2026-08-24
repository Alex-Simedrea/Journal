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
    var originLocation: Location?
    var destinationLocation: Location?
    var startTime: Date
    var endTime: Date
    var isSaving = false
    var errorMessage: String?

    private let hadCompleteTime: Bool
    @ObservationIgnored private var resolvedOriginTimeZoneIdentifier: String?
    @ObservationIgnored private var resolvedDestinationTimeZoneIdentifier: String?
    @ObservationIgnored private let airportResolver:
        (_ code: String, _ cityName: String) async -> Location?

    init(
        pendingImport: PendingBoardingPassImport,
        airportResolver: @escaping (
            _ code: String,
            _ cityName: String
        ) async -> Location? = { code, cityName in
            await AirportLocationResolver.resolve(
                iataCode: code,
                cityName: cityName
            )
        }
    ) {
        self.pendingImport = pendingImport
        self.airportResolver = airportResolver
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

    func prepare(places: [Place], transitTypes: [TransitType]) async {
        if transitType.isEmpty {
            transitType = transitTypes.first?.canonicalName ?? ""
        }
        if originPlaceID == nil {
            originPlaceID = matchPlace(
                named: originName,
                airportCode: pendingImport.originAirportCode,
                in: places
            )?.id
        }
        if destinationPlaceID == nil {
            destinationPlaceID = matchPlace(
                named: destinationName,
                airportCode: pendingImport.destinationAirportCode,
                in: places
            )?.id
        }

        if isFlightImport,
           originPlaceID == nil,
           originLocation == nil,
           let code = pendingImport.originAirportCode {
            originLocation = await airportResolver(code, originName)
        }
        if isFlightImport,
           destinationPlaceID == nil,
           destinationLocation == nil,
           let code = pendingImport.destinationAirportCode {
            destinationLocation = await airportResolver(code, destinationName)
        }

        let originPlace = places.first { $0.id == originPlaceID }
        let destinationPlace = places.first { $0.id == destinationPlaceID }
        resolveLocalTimesIfNeeded(
            origin: originPlace?.location ?? originLocation,
            destination: destinationPlace?.location ?? destinationLocation
        )
    }

    func makeDraftEntry(places: [Place]) -> LogEntry {
        let origin = places.first { $0.id == originPlaceID }
        let destination = places.first { $0.id == destinationPlaceID }
        let draft = resolvedDraft(
            origin: origin,
            destination: destination
        )
        return TransitEntryStore.makeEntry(
            draft: draft,
            rawInput: nil,
            sourceOrganizationName: pendingImport.organizationName,
            sourceServiceIdentifier: pendingImport.serviceIdentifier
        )
    }

    func commit(
        _ entry: LogEntry,
        selectedPeopleIDs: Set<UUID>,
        in modelContext: ModelContext
    ) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            entry.people = try modelContext.fetch(
                FetchDescriptor<Person>()
            ).filter { selectedPeopleIDs.contains($0.id) }
            if isFlightImport {
                try AirportPlaceStore.attachAirports(
                    to: entry,
                    originCode: pendingImport.originAirportCode,
                    originCityName: originName,
                    destinationCode: pendingImport.destinationAirportCode,
                    destinationCityName: destinationName,
                    in: modelContext
                )
            }
            try TransitEntryStore.insert(entry, in: modelContext)
            _ = try? await EntryWeatherService.populate(entry, in: modelContext)
            return true
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func matchPlace(
        named name: String,
        airportCode: String?,
        in places: [Place]
    ) -> Place? {
        if let airportCode,
           !normalize(airportCode).isEmpty {
            let normalizedCode = normalize(airportCode)
            let codeMatches = places.filter { place in
                normalize(place.name) == normalizedCode
                    || place.aliases.contains {
                        normalize($0) == normalizedCode
                    }
            }
            if codeMatches.count == 1 {
                return codeMatches[0]
            }
            let airportMatches = codeMatches.filter {
                $0.systemImage == .airport
            }
            return airportMatches.count == 1 ? airportMatches[0] : nil
        }

        let searchTerm = normalize(name)
        guard !searchTerm.isEmpty else { return nil }

        let exactNames = places.filter { place in
            normalize(place.name) == searchTerm
        }
        if exactNames.count == 1 {
            return exactNames[0]
        }
        let aliasMatches = places.filter { place in
            place.aliases.contains { alias in
                normalize(alias) == searchTerm
            }
        }
        return aliasMatches.count == 1 ? aliasMatches[0] : nil
    }

    private func resolvedDraft(
        origin: Place?,
        destination: Place?
    ) -> ResolvedTransitDraft {
        let resolvedOriginLocation = origin?.location ?? originLocation
        let resolvedDestinationLocation = destination?.location
            ?? destinationLocation
        var fieldReviews: [TransitFieldReview] = []
        if resolvedOriginLocation == nil {
            fieldReviews.append(
                TransitFieldReview(
                    field: .origin,
                    reason: isFlightImport
                        ? "Confirm the boarding-pass origin airport."
                        : "Confirm the boarding-pass origin."
                )
            )
        }
        if resolvedDestinationLocation == nil {
            fieldReviews.append(
                TransitFieldReview(
                    field: .destination,
                    reason: isFlightImport
                        ? "Confirm the boarding-pass destination airport."
                        : "Confirm the boarding-pass destination."
                )
            )
        }
        if pendingImport.transitTypeName == nil {
            fieldReviews.append(
                TransitFieldReview(
                    field: .transitType,
                    reason: "Confirm the journey’s transit type."
                )
            )
        }
        if !hadCompleteTime {
            fieldReviews.append(
                TransitFieldReview(
                    field: .time,
                    reason: "Confirm the journey’s departure and arrival times."
                )
            )
        }

        return ResolvedTransitDraft(
            transitType: transitType,
            originPlace: origin,
            originLocation: resolvedOriginLocation,
            originRawText: endpointRawText(
                name: originName,
                airportCode: pendingImport.originAirportCode
            ),
            destinationPlace: destination,
            destinationLocation: resolvedDestinationLocation,
            destinationRawText: endpointRawText(
                name: destinationName,
                airportCode: pendingImport.destinationAirportCode
            ),
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
    }

    private func resolveLocalTimesIfNeeded(
        origin: Location?,
        destination: Location?
    ) {
        if resolvedOriginTimeZoneIdentifier != origin?.timeZoneIdentifier,
           let origin {
            resolveLocalTime(for: .origin, using: origin)
        }
        if resolvedDestinationTimeZoneIdentifier
            != destination?.timeZoneIdentifier,
           let destination {
            resolveLocalTime(for: .destination, using: destination)
        }
    }

    private func resolveLocalTime(
        for endpoint: BoardingPassEndpoint,
        using location: Location
    ) {
        guard let identifier = location.timeZoneIdentifier,
              let timeZone = TimeZone(identifier: identifier) else { return }
        switch endpoint {
        case .origin:
            if let date = pendingImport.startLocalDateTime?.date(in: timeZone) {
                startTime = date
            }
            resolvedOriginTimeZoneIdentifier = identifier
        case .destination:
            if let date = pendingImport.endLocalDateTime?.date(in: timeZone) {
                endTime = max(date, startTime.addingTimeInterval(60))
            }
            resolvedDestinationTimeZoneIdentifier = identifier
        }
    }

    private var isFlightImport: Bool {
        normalize(transitType) == normalize("Flight")
    }

    private func endpointRawText(
        name: String,
        airportCode: String?
    ) -> String {
        let trimmedName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let airportCode else { return trimmedName }
        guard !trimmedName.isEmpty else { return airportCode }
        guard normalize(trimmedName) != normalize(airportCode) else {
            return trimmedName
        }
        return "\(trimmedName) (\(airportCode))"
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
