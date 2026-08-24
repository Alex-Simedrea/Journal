import MapKit
import SwiftUI

struct PlaceEditorContent: View {
    let model: PlaceEditorModel
    let onSelectSymbol: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            PlaceEditorDetailsCard(
                model: model,
                onSelectSymbol: onSelectSymbol
            )
            PlaceEditorLocationCard(model: model)
        }
    }
}

private struct PlaceEditorDetailsCard: View {
    let model: PlaceEditorModel
    let onSelectSymbol: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Details")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                PlaceNameField(model: model)

                Divider()
                    .padding(.leading, 14)

                PlaceSymbolSelectionButton(
                    model: model,
                    action: onSelectSymbol
                )
            }
            .dynamicSheetSurface()
        }
    }
}

private struct PlaceNameField: View {
    @Bindable var model: PlaceEditorModel
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Name", text: $model.name)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .focused($isFocused)
            .onSubmit {
                isFocused = false
                model.nameSubmitted()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
    }
}

private struct PlaceSymbolSelectionButton: View {
    let model: PlaceEditorModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text("Symbol")
                    .foregroundStyle(.primary)

                Spacer()

                PlaceEditorSymbolImage(
                    systemImage: model.selectedSymbol,
                    isLoading: model.isSuggestingSymbol
                )

                DisclosureChevron()
            }
            .contentShape(.rect)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

private struct PlaceEditorLocationCard: View {
    let model: PlaceEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                LocationSearchField(
                    service: model.locationSearch,
                    isResolving: model.isResolvingSearch,
                    onSelect: model.selectSearchSuggestion
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 9)

                Divider()
                    .padding(.leading, 14)

                PlaceEditorLocationState(model: model)
            }
            .dynamicSheetSurface()
        }
    }
}

private struct PlaceEditorLocationState: View {
    let model: PlaceEditorModel

    var body: some View {
        VStack(spacing: 0) {
            if let location = model.location {
                PlaceEditorSelectedLocation(
                    location: location,
                    model: model
                )
            } else if model.isLoadingLocation {
                PlaceEditorLocationLoading()
            } else {
                PlaceEditorLocationUnavailable(
                    message: model.locationErrorMessage,
                    model: model
                )
            }
        }
    }
}

private struct PlaceEditorSelectedLocation: View {
    let location: Location
    @Bindable var model: PlaceEditorModel

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $model.mapPosition) {
                if model.accuracyRadiusMeters > 0 {
                    MapCircle(
                        center: location.coordinate,
                        radius: model.accuracyRadiusMeters
                    )
                    .foregroundStyle(.blue.opacity(0.12))
                    .stroke(.blue.opacity(0.55), lineWidth: 1.5)
                }
            }
            .onMapCameraChange(
                frequency: .onEnd,
                model.mapCameraChanged
            )
            .onAppear { model.mapDidAppear() }
            .onDisappear { model.mapDidDisappear() }
            .overlay {
                MapSelectionPin()
                    .offset(y: -23.5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .topTrailing) {
                if model.allowsCurrentLocationCapture {
                    CurrentLocationMapButton(
                        isResolving: model.isLoadingLocation
                            || model.isResolvingSearch
                    ) {
                        Task { await model.captureCurrentLocation() }
                    }
                    .padding(12)
                }
            }
            .frame(height: 220)
            .clipShape(.rect(cornerRadius: 16))
            .padding(10)

            Divider()
                .padding(.leading, 14)

            PlaceEditorAddressRow(
                address: location.presentationAddress
            )

            Divider()
                .padding(.leading, 14)

            PlaceEditorAreaControl(model: model)
        }
    }
}

private struct PlaceEditorAddressRow: View {
    let address: String?

    var body: some View {
        Label {
            Text(address ?? "No street address found")
                .foregroundStyle(address == nil ? .secondary : .primary)
                .lineLimit(2)
        } icon: {
            Image(systemName: "location.fill")
                .foregroundStyle(.secondary)
                .frame(width: 24)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct PlaceEditorAreaControl: View {
    @Bindable var model: PlaceEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Area") {
                PlaceEditorAreaLabel(
                    radiusMeters: model.accuracyRadiusMeters
                )
            }

            Slider(
                value: $model.accuracyRadiusMeters,
                in: 0...5_000,
                step: 25
            ) {
                Text("Location area radius")
            } minimumValueLabel: {
                Image(systemName: "mappin")
                    .accessibilityLabel("Exact point")
            } maximumValueLabel: {
                Image(systemName: "circle.dashed")
                    .accessibilityLabel("Five kilometer radius")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct PlaceEditorAreaLabel: View {
    let radiusMeters: Double

    var body: some View {
        if radiusMeters == 0 {
            Text("Exact point")
                .foregroundStyle(.secondary)
        } else {
            Text(
                Measurement(value: radiusMeters, unit: UnitLength.meters),
                format: .measurement(width: .abbreviated)
            )
        }
    }
}

private struct PlaceEditorLocationLoading: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Finding your location…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private struct PlaceEditorLocationUnavailable: View {
    let message: String?
    let model: PlaceEditorModel

    var body: some View {
        ContentUnavailableView {
            Label("Location Unavailable", systemImage: "location.slash")
        } description: {
            Text(
                message ?? (model.allowsCurrentLocationCapture
                    ? "Your location could not be determined."
                    : "Search for a location above to place it on the map.")
            )
        } actions: {
            if model.allowsCurrentLocationCapture {
                Button("Try Again") {
                    Task { await model.captureCurrentLocation() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .padding(.horizontal, 10)
    }
}
