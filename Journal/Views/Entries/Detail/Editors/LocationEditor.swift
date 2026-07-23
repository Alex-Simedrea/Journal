import PhotosUI
import SwiftUI

struct EntryDetailLocationEditor: View {
    @Bindable var session: EntryDetailEditSession
    let role: EntryDetailLocationRole
    let places: [Place]
    let onSaveAsPlace: () -> Void

    @State private var model = EntryLocationPickerModel()

    var body: some View {
        VStack(spacing: 12) {
            if let selection = session.selection(for: role) {
                EntrySelectedLocationCard(selection: selection)
                if selection.placeID == nil {
                    Button(action: onSaveAsPlace) {
                        Label("Save as Place", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.background, in: .rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }

            EntryEditorSection(title: "Search") {
                LocationSearchField(
                    service: model.search,
                    isResolving: model.isResolving
                ) { suggestion in
                    Task {
                        if let selection = await model.resolve(suggestion) {
                            session.setSelection(selection, for: role)
                        }
                    }
                }
                if let errorMessage = model.errorMessage {
                    Label(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                Button {
                    Task {
                        if let selection = await model.currentLocation() {
                            session.setSelection(selection, for: role)
                        }
                    }
                } label: {
                    Label("Current Location", systemImage: "location.fill")
                }
                .disabled(model.isResolving)
            }

            EntryEditorSection(title: "Saved Places") {
                if places.isEmpty {
                    Text("No saved places")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(places, id: \.id) { place in
                        Button {
                            session.setSelection(
                                EntryLocationSelection(place: place),
                                for: role
                            )
                        } label: {
                            HStack(spacing: 10) {
                                TimelineFixedPlaceSymbol(
                                    systemImage: place.systemImage,
                                    size: 24
                                )
                                Text(place.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if session.selection(for: role)?.placeID
                                    == place.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct EntrySelectedLocationCard: View {
    let selection: EntryLocationSelection

    var body: some View {
        HStack(spacing: 12) {
            TimelineFixedPlaceSymbol(
                systemImage: selection.systemImage,
                size: 30
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.title).font(.headline)
                if let address = selection.location.presentationAddress {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(.background, in: .rect(cornerRadius: 18))
    }
}
