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
                }

            NavigationLink {
                PlaceSymbolPicker(selection: $model.selectedSymbol)
                    .onAppear { model.mapDidDisappear() }
            } label: {
                LabeledContent("Symbol") {
                    PlaceEditorSymbolImage(systemImage: model.selectedSymbol)
                }
            }
        }
    }
}

struct PlaceEditorSymbolImage: View {
    let systemImage: PlaceSystemImage

    var body: some View {
        PlaceSymbolImage(systemImage: systemImage)
            .font(.title3)
    }
}
