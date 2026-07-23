import MapKit
import SwiftData
import SwiftUI

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
