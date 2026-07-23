import PhotosUI
import SwiftUI

struct EntryDetailTransitEditor: View {
    @Bindable var session: EntryDetailEditSession
    let transitTypes: [TransitType]

    var body: some View {
        EntryEditorSection(title: "Transit") {
            Picker("Type", selection: $session.transitType) {
                ForEach(transitTypes) { type in
                    Text(type.canonicalName).tag(type.canonicalName)
                }
                if !session.transitType.isEmpty,
                   !transitTypes.contains(where: {
                       $0.canonicalName == session.transitType
                   }) {
                    Text(session.transitType).tag(session.transitType)
                }
            }
            TextField("Operator or issuer", text: $session.transitOperator)
            TextField(
                "Service identifier",
                text: $session.transitServiceIdentifier
            )
            .textInputAutocapitalization(.characters)
        }
    }
}
