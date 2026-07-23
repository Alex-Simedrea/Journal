//
//  EntryLocationPickerSheet.swift
//  Journal
//

import SwiftUI

struct EntryLocationPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: LocalizedStringKey
    let places: [Place]
    let onSelect: (EntryLocationSelection) -> Void

    @State private var model = EntryLocationPickerModel()

    var body: some View {
        NavigationStack {
            List {
                EntryLocationSearchSection(
                    model: model,
                    onSelect: select
                )
                EntryCurrentLocationSection(
                    model: model,
                    onSelect: select
                )
                EntrySavedLocationsSection(
                    places: places,
                    onSelect: select
                )
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
        }
    }

    private func select(_ selection: EntryLocationSelection) {
        onSelect(selection)
        dismiss()
    }
}

private struct EntryLocationSearchSection: View {
    let model: EntryLocationPickerModel
    let onSelect: (EntryLocationSelection) -> Void

    var body: some View {
        Section("Search") {
            LocationSearchField(
                service: model.search,
                isResolving: model.isResolving
            ) { suggestion in
                Task {
                    if let selection = await model.resolve(suggestion) {
                        onSelect(selection)
                    }
                }
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct EntryCurrentLocationSection: View {
    let model: EntryLocationPickerModel
    let onSelect: (EntryLocationSelection) -> Void

    var body: some View {
        Section {
            Button {
                Task {
                    if let selection = await model.currentLocation() {
                        onSelect(selection)
                    }
                }
            } label: {
                Label("Current Location", systemImage: "location.fill")
            }
            .disabled(model.isResolving)
        }
    }
}

private struct EntrySavedLocationsSection: View {
    let places: [Place]
    let onSelect: (EntryLocationSelection) -> Void

    var body: some View {
        Section("Saved Places") {
            if places.isEmpty {
                ContentUnavailableView(
                    "No Saved Places",
                    systemImage: "mappin.slash",
                    description: Text("Search for any location above.")
                )
            } else {
                ForEach(places) { place in
                    EntrySavedLocationButton(
                        place: place,
                        onSelect: onSelect
                    )
                }
            }
        }
    }
}

private struct EntrySavedLocationButton: View {
    let place: Place
    let onSelect: (EntryLocationSelection) -> Void

    var body: some View {
        Button {
            onSelect(EntryLocationSelection(place: place))
        } label: {
            HStack(spacing: 12) {
                PlaceSymbolImage(systemImage: place.systemImage)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .foregroundStyle(.primary)
                    if let address = place.location.compactAddress {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

struct EntryLocationSelectionButton: View {
    let label: LocalizedStringKey
    let title: String?
    let systemImage: PlaceSystemImage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LabeledContent(label) {
                HStack(spacing: 8) {
                    Text(title ?? String(localized: "Choose Location"))
                        .foregroundStyle(title == nil ? .secondary : .primary)
                    PlaceSymbolImage(systemImage: systemImage)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}
