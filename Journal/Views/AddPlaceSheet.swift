//
//  AddPlaceSheet.swift
//  Journal
//

import MapKit
import SwiftData
import SwiftUI

struct AddPlaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let onSave: ((Place) -> Void)?
    private let capturesCurrentLocation: Bool
    @State private var model: PlaceEditorModel

    init(
        initialName: String = "",
        initialSearchQuery: String = "",
        initialLocation: Location? = nil,
        capturesCurrentLocation: Bool = true,
        onSave: ((Place) -> Void)? = nil
    ) {
        self.onSave = onSave
        self.capturesCurrentLocation = capturesCurrentLocation
        _model = State(
            initialValue: PlaceEditorModel(
                initialName: initialName,
                initialSearchQuery: initialSearchQuery,
                initialLocation: initialLocation,
                allowsCurrentLocationCapture: capturesCurrentLocation
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                PlaceEditorDetailsSection(model: model)
                PlaceEditorLocationSection(model: model)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        if let place = model.insertPlace(in: modelContext) {
                            onSave?(place)
                            dismiss()
                        }
                    }
                    .disabled(!model.canSave)
                }
            }
            .alert(
                "Couldn’t Save Place",
                isPresented: Binding(
                    get: { model.saveErrorMessage != nil },
                    set: { if !$0 { model.saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.saveErrorMessage ?? "An unknown error occurred.")
            }
        }
        .task {
            if capturesCurrentLocation, model.location == nil {
                await model.captureCurrentLocation()
            }
        }
        .onDisappear {
            model.stop()
        }
    }
}

struct PlaceEditorDetailsSection: View {
    @Bindable var model: PlaceEditorModel
    @FocusState private var isNameFocused: Bool

    var body: some View {
        Section("Details") {
            TextField("Name", text: $model.name)
                .focused($isNameFocused)
                .submitLabel(.done)
                .onSubmit {
                    isNameFocused = false
                    model.nameSubmitted()
                }

            NavigationLink {
                PlaceSymbolPicker(selection: $model.selectedSymbol)
            } label: {
                LabeledContent("Symbol") {
                    PlaceEditorSymbolImage(
                        systemImage: model.selectedSymbol,
                        isLoading: model.isSuggestingSymbol
                    )
                }
            }
        }
    }
}

struct PlaceEditorSymbolImage: View {
    let systemImage: PlaceSystemImage
    let isLoading: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PlaceSymbolImage(systemImage: systemImage)
            .font(.title3)
            .opacity(isLoading && reduceMotion ? 0.5 : 1)
            .keyframeAnimator(
                initialValue: 1.0,
                repeating: isLoading && !reduceMotion
            ) { content, opacity in
                content.opacity(opacity)
            } keyframes: { _ in
                CubicKeyframe(0.35, duration: 0.65)
                CubicKeyframe(1, duration: 0.65)
            }
    }
}

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
