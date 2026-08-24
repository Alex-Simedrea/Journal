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
    @State private var route: AddPlaceRoute = .editor
    @State private var movesForward = true
    @State private var isScrolled = false
    @State private var chromeHeight: CGFloat = 0

    init(
        initialName: String = "",
        initialSearchQuery: String = "",
        initialLocation: Location? = nil,
        initialSymbol: PlaceSystemImage = .mappin,
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
                initialSymbol: initialSymbol,
                allowsCurrentLocationCapture: capturesCurrentLocation
            )
        )
    }

    var body: some View {
        @Bindable var model = model

        DynamicSheet(sizing: .expanded) {
            DynamicSheetNavigationContainer(
                route: route,
                movesForward: movesForward,
                title: route.title,
                isScrolled: isScrolled,
                chromeHeight: $chromeHeight
            ) {
                switch route {
                case .editor:
                    DynamicSheetScrollView(
                        fillsAvailableHeight: true,
                        topContentInset: chromeHeight,
                        isScrolled: $isScrolled
                    ) {
                        PlaceEditorContent(
                            model: model,
                            onSelectSymbol: {
                                model.mapDidDisappear()
                                movesForward = true
                                isScrolled = false
                                route = .symbols
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                case .symbols:
                    DynamicSheetScrollView(
                        fillsAvailableHeight: true,
                        topContentInset: chromeHeight,
                        isScrolled: $isScrolled
                    ) {
                        PlaceSymbolGrid(selection: $model.selectedSymbol)
                    }
                }
            } leading: {
                Button(action: leadingAction) {
                    Image(
                        systemName: route == .editor
                            ? "xmark"
                            : "chevron.left"
                    )
                    .font(.title2)
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(
                    route == .editor ? "Close" : "Back"
                )
            } trailing: {
                if route == .editor {
                    Button(action: save) {
                        Image(systemName: "checkmark")
                            .font(.title2)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(.blue)
                    .disabled(!model.canSave)
                    .accessibilityLabel("Save Place")
                }
            } accessory: {
                EmptyView()
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
        .task {
            if capturesCurrentLocation, model.location == nil {
                await model.captureCurrentLocation()
            }
        }
        .onDisappear {
            model.stop()
        }
    }

    private func leadingAction() {
        if route == .editor {
            dismiss()
        } else {
            movesForward = false
            isScrolled = false
            route = .editor
        }
    }

    private func save() {
        guard let place = model.insertPlace(in: modelContext) else { return }
        onSave?(place)
        dismiss()
    }
}

private enum AddPlaceRoute: Equatable {
    case editor
    case symbols

    var title: LocalizedStringResource {
        switch self {
        case .editor: "New Place"
        case .symbols: "Symbol"
        }
    }
}
