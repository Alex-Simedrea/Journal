import SwiftUI

struct EntryDetailAddPersonEditor: View {
    @Bindable var session: EntryDetailEditSession

    var body: some View {
        EditorCardSection(title: "Details") {
            TextField("Name", text: $session.newPersonName)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
        }
    }
}
