import MapKit
import SwiftData
import SwiftUI

struct PlaceEditorLocationSection: View {
    let model: PlaceEditorModel

    var body: some View {
        Section("Location") {
            LocationSearchField(
                service: model.locationSearch,
                isResolving: model.isResolvingSearch,
                onSelect: model.selectSearchSuggestion
            )

            if let searchErrorMessage = model.searchErrorMessage {
                Label(
                    searchErrorMessage,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }

            PlaceEditorLocationContent(model: model)
        }
    }
}

private struct PlaceEditorLocationContent: View {
    let model: PlaceEditorModel

    var body: some View {
        if let location = model.location {
            SelectedLocationView(location: location, model: model)
        } else if model.isLoadingLocation {
            LoadingLocationView()
        } else {
            UnavailableLocationView(
                message: model.locationErrorMessage,
                model: model,
                allowsCurrentLocationCapture:
                    model.allowsCurrentLocationCapture
            )
        }
    }
}

private struct SelectedLocationView: View {
    let location: Location
    @Bindable var model: PlaceEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                .overlay {
                    MapSelectionPin()
                        .offset(y: -23.5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .frame(height: 220)
                .clipShape(.rect(cornerRadius: 12))

            LocationAddressLabel(address: location.formattedAddress)
            PlaceAccuracyRadiusControl(model: model)
        }
        .padding(.vertical, 4)
    }
}

private struct PlaceAccuracyRadiusControl: View {
    @Bindable var model: PlaceEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Area") {
                PlaceAccuracyRadiusLabel(
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
    }
}

private struct PlaceAccuracyRadiusLabel: View {
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

private struct LocationAddressLabel: View {
    let address: String?

    var body: some View {
        Label {
            Text(address ?? "No street address found")
                .foregroundStyle(address == nil ? .secondary : .primary)
        } icon: {
            Image(systemName: "location.fill")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}

private struct LoadingLocationView: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Finding your location…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }
}

private struct UnavailableLocationView: View {
    let message: String?
    let model: PlaceEditorModel
    let allowsCurrentLocationCapture: Bool

    var body: some View {
        ContentUnavailableView {
            Label("Location Unavailable", systemImage: "location.slash")
        } description: {
            Text(
                message ?? (allowsCurrentLocationCapture
                    ? "Your location could not be determined."
                    : "Search for the workout location above to place it on the map.")
            )
        } actions: {
            if allowsCurrentLocationCapture {
                Button("Try Again") {
                    Task { await model.captureCurrentLocation() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 190)
    }
}
