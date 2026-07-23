//
//  LocationSearchService.swift
//  Journal
//

import MapKit
import Observation

struct LocationSearchSuggestion: Identifiable {
    let completion: MKLocalSearchCompletion

    var id: String {
        completion.title + completion.subtitle
    }

    var title: String { completion.title }
    var subtitle: String { completion.subtitle }
}

@MainActor
@Observable
final class LocationSearchService: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" {
        didSet {
            errorMessage = nil

            guard hasSearchQuery else {
                suggestions = []
                return
            }

            completer.queryFragment = query
        }
    }

    private(set) var suggestions: [LocationSearchSuggestion] = []
    private(set) var errorMessage: String?

    private let completer = MKLocalSearchCompleter()

    private var hasSearchQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func updateRegion(_ region: MKCoordinateRegion) {
        completer.region = region
    }

    func resolve(_ suggestion: LocationSearchSuggestion) async throws -> MKMapItem {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        let response = try await MKLocalSearch(request: request).start()

        guard let mapItem = response.mapItems.first else {
            throw LocationSearchError.noResults
        }

        return mapItem
    }

    func clear() {
        query = ""
        suggestions = []
        errorMessage = nil
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard hasSearchQuery else {
            suggestions = []
            return
        }

        suggestions = completer.results
            .prefix(6)
            .map(LocationSearchSuggestion.init)
    }

    func completer(
        _ completer: MKLocalSearchCompleter,
        didFailWithError error: any Error
    ) {
        guard hasSearchQuery else {
            suggestions = []
            errorMessage = nil
            return
        }

        suggestions = []
        errorMessage = error.localizedDescription
    }
}

enum LocationSearchError: LocalizedError {
    case noResults

    var errorDescription: String? {
        "No matching location could be found."
    }
}
