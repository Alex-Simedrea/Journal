//
//  EntryDetailSheet.swift
//  Journal
//

import SwiftData
import SwiftUI

struct EntryDetailDraftPresentation {
    let title: LocalizedStringResource
    let isConfirming: Bool
    let onCancel: () -> Void
    let onConfirm: (LogEntry) -> Void
}

struct EntryDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Person.name) private var people: [Person]
    @Query(sort: \Place.name) private var places: [Place]
    @Query private var allEntries: [LogEntry]
    @Query(sort: \TransitType.canonicalName) private var transitTypes:
        [TransitType]

    let entry: LogEntry
    let draftPresentation: EntryDetailDraftPresentation?

    @State private var coordinator: EntryDetailCoordinator
    @State private var routeModel = WorkoutRouteModel()
    @State private var locationPickerModel = EntryLocationPickerModel()
    @State private var addPlaceModel: PlaceEditorModel?
    @State private var isDeleteConfirmationPresented = false
    @State private var contentIsScrolled = false
    @State private var chromeHeight: CGFloat = 0
    @State private var peopleSearchText = ""
    @State private var timeZoneSearchText = ""
    @State private var timeZoneDraft = TimeZone.current.identifier
    @State private var isPhotoPickerPresented = false

    init(entry: LogEntry) {
        self.entry = entry
        draftPresentation = nil
        _coordinator = State(initialValue: EntryDetailCoordinator(entry: entry))
    }

    init(
        draftEntry: LogEntry,
        title: LocalizedStringResource,
        isConfirming: Bool = false,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (LogEntry) -> Void
    ) {
        entry = draftEntry
        draftPresentation = EntryDetailDraftPresentation(
            title: title,
            isConfirming: isConfirming,
            onCancel: onCancel,
            onConfirm: onConfirm
        )
        _coordinator = State(initialValue: EntryDetailCoordinator(entry: entry))
    }

    var body: some View {
        DynamicSheet(sizing: sheetSizing) {
            DynamicSheetNavigationContainer(
                route: coordinator.route,
                movesForward: coordinator.movesForward,
                title: headerTitle,
                isScrolled: contentIsScrolled,
                chromeHeight: $chromeHeight
            ) {
                routeContent
            } leading: {
                if coordinator.route == .details {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Close")
                } else {
                    Button(action: { coordinator.goBack() }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Back")
                }
            } trailing: {
                if coordinator.route == .details, let draftPresentation {
                    Button {
                        draftPresentation.onConfirm(entry)
                    } label: {
                        if draftPresentation.isConfirming {
                            ProgressView()
                                .frame(width: 32, height: 32)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.title2)
                                .frame(width: 32, height: 32)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(.blue)
                    .disabled(
                        draftPresentation.isConfirming || !canConfirmDraft
                    )
                    .accessibilityLabel("Import Journey")
                } else if coordinator.route == .details,
                    entry.entryKindReviewReason != nil
                {
                    Button(action: { coordinator.present(.entryKind) }) {
                        ReviewBadge()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Review entry type")
                } else if coordinator.route.hasConfirmationAction {
                    HStack(spacing: 8) {
                        if coordinator.route == .people {
                            Button {
                                coordinator.present(.addPerson)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .accessibilityLabel("Add Person")
                        }

                        if coordinator.route == .photos {
                            Button {
                                isPhotoPickerPresented = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .accessibilityLabel("Add Photos")
                        }

                        Button(action: saveCurrentRoute) {
                            Image(systemName: "checkmark")
                                .font(.title2)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .tint(.blue)
                        .disabled(!canConfirmCurrentRoute)
                        .accessibilityLabel("Done")
                    }
                }
            } accessory: {
                if coordinator.route == .people {
                    SearchField(
                        prompt: "Search People",
                        text: $peopleSearchText,
                        capitalization: .words
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                } else if case .timeZone = coordinator.route {
                    SearchField(
                        prompt: "Search Time Zones",
                        text: $timeZoneSearchText,
                        capitalization: .words
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                } else if case .location = coordinator.route {
                    EntryLocationSearchField(model: locationPickerModel)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
        }
        .interactiveDismissDisabled(
            draftPresentation != nil || coordinator.isDirty
        )
        .confirmationDialog(
            "Delete Entry?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Entry", role: .destructive, action: deleteEntry)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .alert(
            "Couldn’t Save Changes",
            isPresented: Binding(
                get: { coordinator.errorMessage != nil },
                set: { if !$0 { coordinator.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(coordinator.errorMessage ?? "An unknown error occurred.")
        }
        .onChange(of: coordinator.route) {
            contentIsScrolled = false
            if coordinator.route != .people {
                peopleSearchText = ""
            }
            if coordinator.route != .timeZone(.start),
               coordinator.route != .timeZone(.end) {
                timeZoneSearchText = ""
            }
            if coordinator.route != .photos {
                isPhotoPickerPresented = false
            }
            switch coordinator.route {
            case .addPlace, .placeSymbol:
                break
            default:
                addPlaceModel?.stop()
                addPlaceModel = nil
            }
            if case .location = coordinator.route { return }
            locationPickerModel.stop()
        }
        .onDisappear {
            addPlaceModel?.stop()
        }
    }

    private var sheetSizing: DynamicSheetSizing {
        switch coordinator.route {
        case .people, .timeZone, .location, .addPlace, .placeSymbol:
            .expanded
        case .transitMetadata:
            .fixed(
                DynamicSheetWindowMetrics.maximumContentHeight(
                    bottomClearance: 200
                )
            )
        default:
            .content
        }
    }

    private var headerTitle: LocalizedStringResource {
        if coordinator.route == .details, let draftPresentation {
            return draftPresentation.title
        }
        return coordinator.route == .details
            ? entry.kind.detailTitle
            : coordinator.route.title
    }

    @ViewBuilder
    private var routeContent: some View {
        switch coordinator.route {
        case .details:
            EntryDetailOverview(
                entry: entry,
                routeModel: routeModel,
                topContentInset: chromeHeight,
                isScrolled: $contentIsScrolled,
                onPresent: coordinator.present,
                onDelete: { isDeleteConfirmationPresented = true },
                showsDestructiveActions: draftPresentation == nil
            )
        case .time:
            EntryDetailEditorViewport(
                maximumHeight: DynamicSheetWindowMetrics.maximumContentHeight(
                    bottomClearance: 50
                ),
                topContentInset: chromeHeight,
                isScrolled: $contentIsScrolled
            ) {
                EntryDetailTimeEditor(
                    session: coordinator.session,
                    mapKitRequest: mapKitRouteRequest,
                    showsMapKitPreset: entry.kind == .transit,
                    onSelectTimeZone: presentTimeZone
                )
            }
        case .timeZone(let endpoint):
            TimeZoneEditor(
                selection: $timeZoneDraft,
                searchText: $timeZoneSearchText,
                isScrolled: $contentIsScrolled,
                date: timeZoneDate(for: endpoint),
                topContentInset: chromeHeight
            )
        case .people:
            EntryDetailPeopleEditor(
                session: coordinator.session,
                topContentInset: chromeHeight,
                isScrolled: $contentIsScrolled,
                searchText: $peopleSearchText,
                people: people,
                usageCounts: peopleUsageCounts
            )
        case .photos:
            EntryDetailEditorViewport(
                topContentInset: chromeHeight,
                isScrolled: $contentIsScrolled
            ) {
                EntryDetailPhotosEditor(
                    session: coordinator.session,
                    isPickerPresented: $isPhotoPickerPresented
                )
            }
        case .transitMetadata:
            EntryDetailTransitEditor(
                session: coordinator.session,
                transitTypes: transitTypes,
                topContentInset: chromeHeight,
                isScrolled: $contentIsScrolled
            )
        case .locations:
            EntryDetailEditorViewport(
                topContentInset: chromeHeight,
                isScrolled: $contentIsScrolled
            ) {
                EntryDetailLocationsEditor(
                    entry: entry,
                    session: coordinator.session,
                    onSelect: { coordinator.present(.location($0)) }
                )
            }
        case .location(let role):
            EntryDetailLocationEditor(
                session: coordinator.session,
                role: role,
                places: places,
                model: locationPickerModel,
                topContentInset: chromeHeight,
                isScrolled: $contentIsScrolled,
                onSaveAsPlace: {
                    let selection = coordinator.session.selection(for: role)
                    let name = selection?.title ?? ""
                    coordinator.session.newPlaceName = name
                    addPlaceModel = PlaceEditorModel(
                        initialName: name,
                        initialLocation: selection?.location,
                        allowsCurrentLocationCapture: true
                    )
                    coordinator.present(.addPlace(role))
                }
            )
        case .entryKind:
            EntryDetailEditorViewport(
                topContentInset: chromeHeight,
                isScrolled: $contentIsScrolled
            ) {
                EntryDetailKindEditor(
                    session: coordinator.session,
                    entry: entry,
                    transitTypes: transitTypes
                )
            }
        case .addPerson:
            EntryDetailEditorViewport(
                topContentInset: chromeHeight,
                isScrolled: $contentIsScrolled
            ) {
                EntryDetailAddPersonEditor(session: coordinator.session)
            }
        case .addPlace(let role):
            DynamicSheetScrollView(
                fillsAvailableHeight: true,
                topContentInset: chromeHeight,
                isScrolled: $contentIsScrolled
            ) {
                if let addPlaceModel {
                    PlaceEditorContent(
                        model: addPlaceModel,
                        onSelectSymbol: {
                            coordinator.present(.placeSymbol(role))
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        case .placeSymbol:
            DynamicSheetScrollView(
                fillsAvailableHeight: true,
                topContentInset: chromeHeight,
                isScrolled: $contentIsScrolled
            ) {
                if let addPlaceModel {
                    @Bindable var addPlaceModel = addPlaceModel
                    PlaceSymbolGrid(
                        selection: $addPlaceModel.selectedSymbol
                    )
                }
            }
        case .advanced:
            EntryDetailEditorViewport(
                topContentInset: chromeHeight,
                isScrolled: $contentIsScrolled
            ) {
                EntryDetailAdvancedEditor(entry: entry)
            }
        }
    }

}

private struct EntryDetailEditorViewport<Content: View>: View {
    let maximumHeight: CGFloat?
    let topContentInset: CGFloat
    @Binding var isScrolled: Bool
    let content: Content

    init(
        maximumHeight: CGFloat? = nil,
        topContentInset: CGFloat,
        isScrolled: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.maximumHeight = maximumHeight
        self.topContentInset = topContentInset
        _isScrolled = isScrolled
        self.content = content()
    }

    var body: some View {
        DynamicSheetScrollView(
            maximumHeight: maximumHeight,
            topContentInset: topContentInset,
            isScrolled: $isScrolled
        ) {
            content
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 18)
        }
    }
}

private extension EntryDetailSheet {
    private func close() {
        if let draftPresentation {
            draftPresentation.onCancel()
        } else {
            dismiss()
        }
    }

    private var canConfirmDraft: Bool {
        guard let details = entry.transitDetails,
              !details.type.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty,
              let startTime = entry.startTime,
              let endTime = entry.endTime else {
            return false
        }
        let hasOrigin = details.originPlace != nil
            || details.originLocation != nil
            || !(details.originRawText ?? "").trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        let hasDestination = details.destinationPlace != nil
            || details.destinationLocation != nil
            || !(details.destinationRawText ?? "").trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        return hasOrigin && hasDestination && endTime > startTime
    }

    private var peopleUsageCounts: [UUID: Int] {
        EntryDetailPeopleUsage.counts(in: allEntries)
    }

    private func saveCurrentRoute() {
        let persist = draftPresentation == nil
        do {
            switch coordinator.route {
            case .time:
                try EntryDetailEditingService.saveTime(
                    entry: entry,
                    session: coordinator.session,
                    in: modelContext,
                    persist: persist
                )
                coordinator.returnToDetails(entry: entry)
            case .timeZone(let endpoint):
                setTimeZoneDraft(for: endpoint)
                coordinator.goBack(discardingChanges: false)
            case .people:
                try EntryDetailEditingService.savePeople(
                    entry: entry,
                    session: coordinator.session,
                    people: people,
                    in: modelContext,
                    persist: persist
                )
                coordinator.returnToDetails(entry: entry)
            case .photos:
                try EntryDetailEditingService.savePhotos(
                    entry: entry,
                    session: coordinator.session,
                    in: modelContext,
                    persist: persist
                )
                coordinator.returnToDetails(entry: entry)
            case .transitMetadata:
                try EntryDetailEditingService.saveTransitMetadata(
                    entry: entry,
                    session: coordinator.session,
                    in: modelContext,
                    persist: persist
                )
                coordinator.returnToDetails(entry: entry)
            case .location(let role):
                try EntryDetailEditingService.saveLocation(
                    entry: entry,
                    role: role,
                    session: coordinator.session,
                    places: places,
                    in: modelContext,
                    persist: persist
                )
                if role == .place {
                    coordinator.returnToDetails(entry: entry)
                } else {
                    coordinator.returnToLocations(entry: entry)
                }
            case .entryKind:
                try EntryDetailEditingService.convertKind(
                    entry: entry,
                    session: coordinator.session,
                    places: places,
                    in: modelContext
                )
                coordinator.returnToDetails(entry: entry)
            case .addPerson:
                try addPerson()
            case .addPlace(let role):
                addPlace(for: role)
            case .details, .locations, .placeSymbol, .advanced:
                break
            }
        } catch {
            coordinator.errorMessage = error.localizedDescription
        }
    }

    private var mapKitRouteRequest: TimeEditorRouteRequest? {
        guard entry.kind == .transit,
              let origin = coordinator.session.selection(for: .origin)?.location,
              let destination = coordinator.session.selection(for: .destination)?.location else {
            return nil
        }

        let selectedType = normalized(coordinator.session.transitType)
        let routingMode = transitTypes.first { type in
            normalized(type.canonicalName) == selectedType
                || type.aliases.contains { normalized($0) == selectedType }
        }?.routingMode ?? .automobile

        return TimeEditorRouteRequest(
            origin: origin,
            destination: destination,
            routingMode: routingMode
        )
    }

    private func presentTimeZone(_ endpoint: EntryTimeZoneEndpoint) {
        timeZoneDraft = switch endpoint {
        case .start: coordinator.session.startTimeZoneIdentifier
        case .end: coordinator.session.endTimeZoneIdentifier
        }
        coordinator.present(.timeZone(endpoint))
    }

    private func timeZoneDate(for endpoint: EntryTimeZoneEndpoint) -> Date {
        switch endpoint {
        case .start: coordinator.session.startTime
        case .end: coordinator.session.endTime
        }
    }

    private func setTimeZoneDraft(for endpoint: EntryTimeZoneEndpoint) {
        switch endpoint {
        case .start:
            coordinator.session.startTimeZoneIdentifier = timeZoneDraft
        case .end:
            coordinator.session.endTimeZoneIdentifier = timeZoneDraft
        }
    }

    private func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addPerson() throws {
        let person = try EntryDetailEditingService.createPerson(
            name: coordinator.session.newPersonName,
            in: modelContext
        )
        coordinator.session.selectedPeopleIDs.insert(person.id)
        coordinator.session.newPersonName = ""
        coordinator.goBack(discardingChanges: false)
    }

    private var canConfirmCurrentRoute: Bool {
        if case .addPlace = coordinator.route {
            return addPlaceModel?.canSave ?? false
        }
        return true
    }

    private func addPlace(for role: EntryDetailLocationRole) {
        guard let addPlaceModel,
              let place = addPlaceModel.insertPlace(in: modelContext) else {
            coordinator.errorMessage =
                addPlaceModel?.saveErrorMessage
                ?? String(localized: "The place could not be saved.")
            return
        }
        coordinator.session.setSelection(
            EntryLocationSelection(place: place),
            for: role
        )
        coordinator.session.newPlaceName = ""
        coordinator.session.newPlaceSystemImage = .mappin
        coordinator.goBack(discardingChanges: false)
        self.addPlaceModel = nil
    }

    private func deleteEntry() {
        do {
            try JournalDeletionService.delete(entry, in: modelContext)
            dismiss()
        } catch {
            coordinator.errorMessage = error.localizedDescription
        }
    }
}
