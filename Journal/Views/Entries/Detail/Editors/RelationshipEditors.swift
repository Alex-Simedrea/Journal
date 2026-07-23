import PhotosUI
import SwiftUI

struct EntryDetailAddPersonEditor: View {
    @Bindable var session: EntryDetailEditSession

    var body: some View {
        EntryEditorSection(title: "Details") {
            TextField("Name", text: $session.newPersonName)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
        }
    }
}

struct EntryDetailAddPlaceEditor: View {
    @Bindable var session: EntryDetailEditSession
    let role: EntryDetailLocationRole

    var body: some View {
        VStack(spacing: 12) {
            if let selection = session.selection(for: role) {
                EntrySelectedLocationCard(selection: selection)
            }
            EntryEditorSection(title: "Details") {
                TextField("Name", text: $session.newPlaceName)
                    .textInputAutocapitalization(.words)
                Picker("Symbol", selection: $session.newPlaceSystemImage) {
                    ForEach(PlaceSystemImage.allCases) { symbol in
                        Label(
                            symbol.rawValue,
                            systemImage: symbol.rawValue
                        )
                        .tag(symbol)
                    }
                }
            }
        }
    }
}
