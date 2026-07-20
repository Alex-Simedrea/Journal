//
//  EntryDetailEditors.swift
//  Journal
//

import PhotosUI
import SwiftUI

struct EntryDetailTimeEditor: View {
    @Bindable var session: EntryDetailEditSession

    var body: some View {
        VStack(spacing: 12) {
            EntryEditorSection(title: "Start") {
                DatePicker("Started", selection: $session.startTime)
                EntryTimeZonePicker(
                    title: "Time zone",
                    selection: $session.startTimeZoneIdentifier
                )
            }
            EntryEditorSection(title: "End") {
                DatePicker(
                    "Ended",
                    selection: $session.endTime,
                    in: session.startTime...
                )
                EntryTimeZonePicker(
                    title: "Time zone",
                    selection: $session.endTimeZoneIdentifier
                )
            }
        }
    }
}

private struct EntryTimeZonePicker: View {
    let title: LocalizedStringResource
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(EntryTimeZoneChoice.all) { choice in
                Text(choice.title).tag(choice.identifier)
            }
        }
    }
}

private struct EntryTimeZoneChoice: Identifiable {
    let identifier: String
    let title: String
    var id: String { identifier }

    static let all: [EntryTimeZoneChoice] = TimeZone
        .knownTimeZoneIdentifiers
        .map {
            EntryTimeZoneChoice(
                identifier: $0,
                title: $0.replacingOccurrences(of: "_", with: " ")
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
}

struct EntryDetailPeopleEditor: View {
    @Bindable var session: EntryDetailEditSession
    let people: [Person]
    let onAddPerson: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onAddPerson) {
                Label("Add Person", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.background, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            if people.isEmpty {
                ContentUnavailableView(
                    "No People",
                    systemImage: "person.2.slash",
                    description: Text("Add someone to select them here.")
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(people) { person in
                        EntryDetailPersonSelectionRow(
                            person: person,
                            selected: session.selectedPeopleIDs.contains(
                                person.id
                            ),
                            onSelect: {
                                if session.selectedPeopleIDs.contains(person.id) {
                                    session.selectedPeopleIDs.remove(person.id)
                                } else {
                                    session.selectedPeopleIDs.insert(person.id)
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

private struct EntryDetailPersonSelectionRow: View {
    let person: Person
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                PersonAvatar(
                    name: person.name,
                    contactIdentifier: person.contactIdentifier,
                    size: 34
                )
                Text(person.name)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        selected ? Color.accentColor : Color.secondary
                    )
            }
            .padding(10)
            .background(.background, in: .rect(cornerRadius: 16))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

struct EntryDetailPhotosEditor: View {
    @Bindable var session: EntryDetailEditSession
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isPickerPresented = false

    var body: some View {
        VStack(spacing: 12) {
            Button {
                isPickerPresented = true
            } label: {
                Label("Add Photos", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.background, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            LazyVStack(spacing: 8) {
                ForEach(session.photoReferences) { reference in
                    HStack(spacing: 10) {
                        EntryDetailPhotoThumbnail(reference: reference)
                            .frame(width: 58, height: 58)
                            .clipShape(.rect(cornerRadius: 12))
                        Text("Attached photo")
                        Spacer()
                        Button(role: .destructive) {
                            session.photoReferences.removeAll {
                                $0.id == reference.id
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    .padding(8)
                    .background(.background, in: .rect(cornerRadius: 16))
                }
            }
        }
        .photosPicker(
            isPresented: $isPickerPresented,
            selection: $selectedItems,
            maxSelectionCount: nil,
            selectionBehavior: .ordered,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selectedItems) { _, items in
            let existing = Set(session.photoReferences.map(\.assetLocalIdentifier))
            let references = items.compactMap { item -> PhotoReference? in
                guard let identifier = item.itemIdentifier,
                      !existing.contains(identifier) else { return nil }
                return PhotoReference(assetLocalIdentifier: identifier)
            }
            session.photoReferences.append(contentsOf: references)
            selectedItems = []
        }
    }
}

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

struct EntryDetailLocationsEditor: View {
    let entry: LogEntry
    let session: EntryDetailEditSession
    let onSelect: (EntryDetailLocationRole) -> Void

    var body: some View {
        VStack(spacing: 10) {
            if entry.kind == .placeVisit
                || entry.workoutDetails?.movementKind != .moving {
                EntryLocationHubButton(
                    role: .place,
                    selection: session.selection(for: .place),
                    onSelect: onSelect
                )
            } else {
                EntryLocationHubButton(
                    role: .origin,
                    selection: session.selection(for: .origin),
                    onSelect: onSelect
                )
                EntryLocationHubButton(
                    role: .destination,
                    selection: session.selection(for: .destination),
                    onSelect: onSelect
                )
            }
        }
    }
}

private struct EntryLocationHubButton: View {
    let role: EntryDetailLocationRole
    let selection: EntryLocationSelection?
    let onSelect: (EntryDetailLocationRole) -> Void

    var body: some View {
        Button { onSelect(role) } label: {
            HStack(spacing: 12) {
                if let selection {
                    TimelineFixedPlaceSymbol(
                        systemImage: selection.systemImage,
                        size: 28
                    )
                } else {
                    TimelineFixedSymbol(
                        systemName: "mappin.slash",
                        size: 28
                    )
                    .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(role.title).font(.headline)
                    Text(selection?.title ?? String(localized: "Needs review"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                EntryDetailChevron()
            }
            .padding()
            .background(.background, in: .rect(cornerRadius: 18))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

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
                    ForEach(places) { place in
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

private struct EntrySelectedLocationCard: View {
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

struct EntryDetailKindEditor: View {
    @Bindable var session: EntryDetailEditSession
    let entry: LogEntry
    let transitTypes: [TransitType]

    var body: some View {
        VStack(spacing: 12) {
            if let reason = entry.entryKindReviewReason {
                Label(reason, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            EntryEditorSection(title: "Entry Type") {
                Picker("Type", selection: $session.targetKind) {
                    Text("Transit").tag(LogKind.transit)
                    Text("Place").tag(LogKind.placeVisit)
                }
                .pickerStyle(.segmented)
                if session.targetKind == .transit {
                    Picker("Transit type", selection: $session.transitType) {
                        ForEach(transitTypes) { type in
                            Text(type.canonicalName).tag(type.canonicalName)
                        }
                    }
                }
            }
            Text("Any fields that cannot be carried across will remain marked for review.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

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

struct EntryDetailAdvancedEditor: View {
    let entry: LogEntry

    var body: some View {
        VStack(spacing: 12) {
            EntryAdvancedValueCard(title: "Original Input", value: entry.rawInputString)
            EntryAdvancedValueCard(title: "Instructions", value: entry.modelInstructions)
            EntryAdvancedValueCard(title: "Prompt", value: entry.modelPrompt)
            EntryAdvancedValueCard(title: "Tool Transcript", value: entry.modelToolTranscript)
            EntryAdvancedValueCard(title: "Response", value: entry.modelResponse)
        }
    }
}

private struct EntryAdvancedValueCard: View {
    let title: LocalizedStringResource
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(value ?? String(localized: "Unavailable"))
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(value == nil ? .secondary : .primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 16))
    }
}

struct EntryEditorSection<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 18))
    }
}
