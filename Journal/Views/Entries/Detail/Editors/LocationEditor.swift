import MapKit
import SwiftUI

struct EntryLocationSearchField: View {
    @Bindable var model: EntryLocationPickerModel

    var body: some View {
        SearchField(
            prompt: "Search Locations",
            text: $model.searchText,
            capitalization: .words
        )
    }
}

struct EntryDetailLocationEditor: View {
    @Bindable var session: EntryDetailEditSession
    let role: EntryDetailLocationRole
    let places: [Place]
    let model: EntryLocationPickerModel
    let topContentInset: CGFloat
    @Binding var isScrolled: Bool
    let linkedCount: Int
    let onEditLinks: () -> Void
    let onSaveAsPlace: () -> Void

    var body: some View {
        DynamicSheetScrollView(
            fillsAvailableHeight: true,
            topContentInset: topContentInset,
            isScrolled: $isScrolled
        ) {
            LocationPickerContent(
                model: model,
                places: EntryLocationPickerProjection.filteredPlaces(
                    places,
                    query: model.searchText
                ),
                linkedCount: linkedCount,
                onEditLinks: onEditLinks,
                onSaveAsPlace: onSaveAsPlace
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .onChange(of: model.selection) { _, selection in
            guard let selection else { return }
            session.setSelection(selection, for: role)
        }
        .onAppear {
            model.prepare(selection: session.selection(for: role))
        }
        .onDisappear {
            model.stop()
        }
    }
}

private struct LocationPickerContent: View {
    let model: EntryLocationPickerModel
    let places: [Place]
    let linkedCount: Int
    let onEditLinks: () -> Void
    let onSaveAsPlace: () -> Void

    var body: some View {
        if model.searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            LocationSelectionContent(
                model: model,
                places: places,
                linkedCount: linkedCount,
                onEditLinks: onEditLinks,
                onSaveAsPlace: onSaveAsPlace
            )
        } else {
            LocationSearchContent(
                model: model,
                places: places
            )
        }
    }
}

private struct LocationSelectionContent: View {
    let model: EntryLocationPickerModel
    let places: [Place]
    let linkedCount: Int
    let onEditLinks: () -> Void
    let onSaveAsPlace: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LocationMapCard(model: model)

            EntryLinkDisclosureRow(
                linkedCount: linkedCount,
                onSelect: onEditLinks
            )

            if let selection = model.selection, selection.placeID == nil {
                SavePlaceButton(action: onSaveAsPlace)
            }

            SavedPlacesSection(
                places: places,
                selectedPlaceID: model.selection?.placeID,
                hasSearchQuery: false,
                onSelect: model.select
            )
        }
    }
}

private struct LocationSearchContent: View {
    let model: EntryLocationPickerModel
    let places: [Place]

    var body: some View {
        LocationSearchResults(
            places: places,
            selectedPlaceID: model.selection?.placeID,
            suggestions: model.search.suggestions,
            searchErrorMessage: model.search.errorMessage,
            resolutionErrorMessage: model.errorMessage,
            isSearching: model.search.isSearching,
            isResolving: model.isResolving,
            onSelectPlace: model.select,
            onSelectSuggestion: { suggestion in
                Task { await model.resolve(suggestion) }
            }
        )
    }
}

private struct LocationSearchResults: View {
    let places: [Place]
    let selectedPlaceID: UUID?
    let suggestions: [LocationSearchSuggestion]
    let searchErrorMessage: String?
    let resolutionErrorMessage: String?
    let isSearching: Bool
    let isResolving: Bool
    let onSelectPlace: (Place) -> Void
    let onSelectSuggestion: (LocationSearchSuggestion) -> Void

    var body: some View {
        let results = EntryLocationPickerProjection.interleavedSearchResults(
            places: places,
            suggestions: suggestions
        )
        VStack(alignment: .leading, spacing: 10) {
            Text("Results")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if !results.isEmpty {
                    ForEach(results) { result in
                        EntryLocationSearchResultRow(
                            result: result,
                            selectedPlaceID: selectedPlaceID,
                            showsDivider: result.id != results.first?.id,
                            onSelectPlace: onSelectPlace,
                            onSelectSuggestion: onSelectSuggestion
                        )
                    }
                }

                if let message = resolutionErrorMessage ?? searchErrorMessage {
                    LocationSearchErrorRow(message: message)
                } else if isResolving || isSearching {
                    LocationSearchLoadingRow()
                } else if results.isEmpty {
                    LocationSearchEmptyRow()
                }
            }
            .dynamicSheetSurface()
        }
    }
}

private struct EntryLocationSearchResultRow: View {
    let result: EntryLocationSearchResult
    let selectedPlaceID: UUID?
    let showsDivider: Bool
    let onSelectPlace: (Place) -> Void
    let onSelectSuggestion: (LocationSearchSuggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch result {
            case .savedPlace(let place):
                SavedPlaceRow(
                    place: place,
                    isSelected: selectedPlaceID == place.id,
                    showsDivider: showsDivider,
                    onSelect: onSelectPlace
                )
            case .mapKit(let suggestion):
                LocationSearchSuggestionRow(
                    suggestion: suggestion,
                    showsDivider: showsDivider,
                    onSelect: onSelectSuggestion
                )
            }
        }
    }
}

private struct LocationSearchSuggestionRow: View {
    let suggestion: LocationSearchSuggestion
    let showsDivider: Bool
    let onSelect: (LocationSearchSuggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider {
                Divider()
                    .padding(.leading, 52)
            }

            Button {
                onSelect(suggestion)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
                .contentShape(.rect)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct LocationSearchErrorRow: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
    }
}

private struct LocationSearchLoadingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Finding location…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}

private struct LocationSearchEmptyRow: View {
    var body: some View {
        Label("No Map Results", systemImage: "magnifyingglass")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
    }
}

private struct LocationMapCard: View {
    @Bindable var model: EntryLocationPickerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Map(position: $model.mapPosition)
                .onMapCameraChange(
                    frequency: .onEnd,
                    model.mapCameraChanged
                )
                .overlay {
                    MapSelectionPin()
                        .offset(y: -23.5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .overlay(alignment: .topTrailing) {
                    CurrentLocationMapButton(
                        isResolving: model.isResolving
                    ) {
                        Task { await model.useCurrentLocation() }
                    }
                    .padding(12)
                }
                .frame(height: 235)
                .clipShape(.rect(cornerRadius: 18))

            LocationMapCaption(selection: model.selection)
        }
        .padding(10)
        .dynamicSheetSurface()
    }
}

private struct LocationMapCaption: View {
    let selection: EntryLocationSelection?

    var body: some View {
        PlaceSummary(
            title: selection?.title ?? String(localized: "Choose a location"),
            address: selection?.location.presentationAddress
                ?? String(localized: "Search above or move the map"),
            systemImage: selection?.systemImage ?? .mappin
        )
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }
}

private struct SavePlaceButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Save Place", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(.white)
                .background(.tint, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.semibold))
    }
}

private struct SavedPlacesSection: View {
    let places: [Place]
    let selectedPlaceID: UUID?
    let hasSearchQuery: Bool
    let onSelect: (Place) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved Places")
                .font(.headline)
                .padding(.horizontal, 4)

            if places.isEmpty {
                SavedPlacesEmptyState(hasSearchQuery: hasSearchQuery)
            } else {
                VStack(spacing: 0) {
                    ForEach(places) { place in
                        SavedPlaceRow(
                            place: place,
                            isSelected: selectedPlaceID == place.id,
                            showsDivider: place.id != places.first?.id,
                            onSelect: onSelect
                        )
                    }
                }
                .dynamicSheetSurface()
            }
        }
    }
}

private struct SavedPlaceRow: View {
    let place: Place
    let isSelected: Bool
    let showsDivider: Bool
    let onSelect: (Place) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider {
                Divider()
                    .padding(.leading, 58)
            }

            Button {
                onSelect(place)
            } label: {
                HStack(spacing: 12) {
                    PlaceSummary(
                        title: place.name,
                        address: place.location.presentationAddress,
                        systemImage: place.systemImage
                    )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(.rect)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isSelected ? "Selected" : "")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

private struct PlaceSummary: View {
    let title: String
    let address: String?
    let systemImage: PlaceSystemImage

    var body: some View {
        HStack(spacing: 12) {
            FixedSizePlaceSymbol(
                systemImage: systemImage,
                size: 28
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let address {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
    }
}

private struct SavedPlacesEmptyState: View {
    let hasSearchQuery: Bool

    var body: some View {
        ContentUnavailableView(
            hasSearchQuery ? "No Matching Places" : "No Saved Places",
            systemImage: "mappin.slash",
            description: Text(
                hasSearchQuery
                    ? "Try another search or choose a MapKit result."
                    : "Search for a location to select it."
            )
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .dynamicSheetSurface()
    }
}
