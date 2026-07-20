//
//  EntryDetailSheet.swift
//  Journal
//

import SwiftData
import SwiftUI

struct EntryDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \Person.name) private var people: [Person]
    @Query(sort: \Place.name) private var places: [Place]
    @Query(sort: \TransitType.canonicalName) private var transitTypes:
        [TransitType]

    let entry: LogEntry

    @State private var coordinator: EntryDetailCoordinator
    @State private var routeModel = WorkoutRouteModel()
    @State private var isDeleteConfirmationPresented = false

    init(entry: LogEntry) {
        self.entry = entry
        _coordinator = State(initialValue: EntryDetailCoordinator(entry: entry))
    }

    var body: some View {
        DynamicPresentationSheet {
            VStack(spacing: 0) {
                EntryDetailSheetHeader(
                    route: coordinator.route,
                    entry: entry,
                    onClose: { dismiss() },
                    onBack: { coordinator.goBack() },
                    onDone: saveCurrentRoute,
                    onReviewKind: { coordinator.present(.entryKind) }
                )

                routeContent
                    .id(coordinator.route.id)
                    .transition(
                        .blurReplace(
                            coordinator.movesForward ? .upUp : .downUp
                        )
                    )
            }
        }
        .interactiveDismissDisabled(coordinator.isDirty)
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
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.25),
            value: coordinator.route
        )
        .sensoryFeedback(
            .impact(flexibility: .soft, intensity: 1),
            trigger: coordinator.route
        )
    }

    @ViewBuilder
    private var routeContent: some View {
        switch coordinator.route {
        case .details:
            EntryDetailOverview(
                entry: entry,
                routeModel: routeModel,
                onPresent: coordinator.present,
                onDelete: { isDeleteConfirmationPresented = true }
            )
        case .time:
            editorViewport {
                EntryDetailTimeEditor(session: coordinator.session)
            }
        case .people:
            editorViewport {
                EntryDetailPeopleEditor(
                    session: coordinator.session,
                    people: people,
                    onAddPerson: { coordinator.present(.addPerson) }
                )
            }
        case .photos:
            editorViewport {
                EntryDetailPhotosEditor(session: coordinator.session)
            }
        case .transitMetadata:
            editorViewport {
                EntryDetailTransitEditor(
                    session: coordinator.session,
                    transitTypes: transitTypes
                )
            }
        case .locations:
            editorViewport {
                EntryDetailLocationsEditor(
                    entry: entry,
                    session: coordinator.session,
                    onSelect: { coordinator.present(.location($0)) }
                )
            }
        case .location(let role):
            editorViewport {
                EntryDetailLocationEditor(
                    session: coordinator.session,
                    role: role,
                    places: places,
                    onSaveAsPlace: {
                        coordinator.session.newPlaceName =
                            coordinator.session
                            .selection(for: role)?.title ?? ""
                        coordinator.present(.addPlace(role))
                    }
                )
            }
        case .entryKind:
            editorViewport {
                EntryDetailKindEditor(
                    session: coordinator.session,
                    entry: entry,
                    transitTypes: transitTypes
                )
            }
        case .addPerson:
            editorViewport {
                EntryDetailAddPersonEditor(session: coordinator.session)
            }
        case .addPlace(let role):
            editorViewport {
                EntryDetailAddPlaceEditor(
                    session: coordinator.session,
                    role: role
                )
            }
        case .advanced:
            editorViewport {
                EntryDetailAdvancedEditor(entry: entry)
            }
        }
    }

    private func editorViewport<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        DynamicSheetScrollView {
            content()
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 18)
        }
    }

    private func saveCurrentRoute() {
        do {
            switch coordinator.route {
            case .time:
                try EntryDetailEditingService.saveTime(
                    entry: entry,
                    session: coordinator.session,
                    in: modelContext
                )
                coordinator.returnToDetails(entry: entry)
            case .people:
                try EntryDetailEditingService.savePeople(
                    entry: entry,
                    session: coordinator.session,
                    people: people,
                    in: modelContext
                )
                coordinator.returnToDetails(entry: entry)
            case .photos:
                try EntryDetailEditingService.savePhotos(
                    entry: entry,
                    session: coordinator.session,
                    in: modelContext
                )
                coordinator.returnToDetails(entry: entry)
            case .transitMetadata:
                try EntryDetailEditingService.saveTransitMetadata(
                    entry: entry,
                    session: coordinator.session,
                    in: modelContext
                )
                coordinator.returnToDetails(entry: entry)
            case .location(let role):
                try EntryDetailEditingService.saveLocation(
                    entry: entry,
                    role: role,
                    session: coordinator.session,
                    places: places,
                    in: modelContext
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
                try addPlace(for: role)
            case .details, .locations, .advanced:
                break
            }
        } catch {
            coordinator.errorMessage = error.localizedDescription
        }
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

    private func addPlace(for role: EntryDetailLocationRole) throws {
        guard let selection = coordinator.session.selection(for: role) else {
            throw EntryDetailEditingError.missingLocation
        }
        let place = try EntryDetailEditingService.createPlace(
            name: coordinator.session.newPlaceName,
            selection: selection,
            systemImage: coordinator.session.newPlaceSystemImage,
            in: modelContext
        )
        coordinator.session.setSelection(
            EntryLocationSelection(place: place),
            for: role
        )
        coordinator.session.newPlaceName = ""
        coordinator.session.newPlaceSystemImage = .mappin
        coordinator.goBack(discardingChanges: false)
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

private struct EntryDetailSheetHeader: View {
    let route: EntryDetailRoute
    let entry: LogEntry
    let onClose: () -> Void
    let onBack: () -> Void
    let onDone: () -> Void
    let onReviewKind: () -> Void

    var body: some View {
        ZStack {
            Text(route == .details ? entry.kind.detailTitle : route.title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            HStack {
                if route == .details {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Close")
                } else {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Back")
                }

                Spacer()

                if route == .details, entry.entryKindReviewReason != nil {
                    Button(action: onReviewKind) {
                        EntryDetailReviewBadge()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Review entry type")
                } else if route.hasConfirmationAction {
                    Button(action: onDone) {
                        Image(systemName: "checkmark")
                            .font(.title2)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(.blue)
                    .accessibilityLabel("Done")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }
}

private struct EntryDetailOverview: View {
    let entry: LogEntry
    let routeModel: WorkoutRouteModel
    let onPresent: (EntryDetailRoute) -> Void
    let onDelete: () -> Void

    var body: some View {
        DynamicSheetScrollView {
            VStack(spacing: 10) {
                EntryDetailMapCard(
                    entry: entry,
                    routeModel: routeModel,
                    needsReview: mapNeedsReview,
                    onEdit: editMap
                )

                switch entry.kind {
                case .placeVisit:
                    placeComposition
                case .transit:
                    transitComposition
                case .workout:
                    workoutComposition
                case .wakeUp:
                    ContentUnavailableView(
                        "Wake-up Details",
                        systemImage: "alarm"
                    )
                }

                EntryDetailSectionButton(
                    title: "Photos",
                    onSelect: { onPresent(.photos) }
                )
                EntryDetailPhotoGrid(references: entry.photoReferences)

                Button {
                    onPresent(.advanced)
                } label: {
                    HStack {
                        Label("Advanced", systemImage: "hammer")
                        Spacer()
                        EntryDetailChevron()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.background, in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
                Button {
                    onDelete()
                } label: {
                    Label("Delete entry", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.background, in: .rect(cornerRadius: 16))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private var placeComposition: some View {
        adaptivePair {
            timeCard(editable: true, needsReview: placeNeedsReview(.time))
            peopleCard(needsReview: placeNeedsReview(.people))
        }
        adaptivePair {
            startWeatherCard
            endWeatherCard
        }
    }

    @ViewBuilder
    private var transitComposition: some View {
        adaptivePair {
            timeCard(editable: true, needsReview: transitNeedsReview(.time))
            if let details = entry.transitDetails {
                EntryDetailTransitCard(
                    details: details,
                    needsReview: transitNeedsReview(.transitType),
                    onEdit: { onPresent(.transitMetadata) }
                )
            } else {
                missingCard("Transit details need review")
            }
        }
        adaptivePair {
            weatherColumn
            peopleCard(needsReview: transitNeedsReview(.people))
        }
    }

    @ViewBuilder
    private var workoutComposition: some View {
        adaptivePair {
            timeCard(editable: false, needsReview: false)
            if let details = entry.workoutDetails {
                EntryDetailWorkoutCard(details: details)
            } else {
                missingCard("Workout details unavailable")
            }
        }
        adaptivePair {
            weatherColumn
            peopleCard(needsReview: false)
        }
    }

    private var weatherColumn: some View {
        VStack(spacing: 7) {
            startWeatherCard
            endWeatherCard
        }
        .frame(maxHeight: .infinity)
    }

    private var startWeatherCard: some View {
        EntryDetailWeatherCard(
            weather: entry.weather,
            location: startLocation,
            placeSystemImage: startPlaceSymbol,
            time: entry.startTime,
            timeZoneIdentifier: entry.startTimeZoneIdentifier
        )
    }

    private var endWeatherCard: some View {
        EntryDetailWeatherCard(
            weather: entry.endWeather,
            location: endLocation,
            placeSystemImage: endPlaceSymbol,
            time: entry.endTime,
            timeZoneIdentifier: entry.endTimeZoneIdentifier
        )
    }

    private func timeCard(editable: Bool, needsReview: Bool) -> some View {
        EntryDetailTimeCard(
            startTime: entry.startTime,
            endTime: entry.endTime,
            startTimeZoneIdentifier: entry.startTimeZoneIdentifier,
            endTimeZoneIdentifier: entry.endTimeZoneIdentifier,
            editable: editable,
            needsReview: needsReview,
            onEdit: { onPresent(.time) }
        )
    }

    private func peopleCard(needsReview: Bool) -> some View {
        EntryDetailPeopleCard(
            people: entry.people,
            needsReview: needsReview,
            onEdit: { onPresent(.people) }
        )
    }

    private func adaptivePair<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            content()
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func missingCard(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(
                maxWidth: .infinity,
                minHeight: 88,
                maxHeight: .infinity
            )
            .background(.background, in: .rect(cornerRadius: 22))
    }

    private func editMap() {
        if entry.kind == .placeVisit
            || entry.workoutDetails?.movementKind != .moving
        {
            onPresent(.location(.place))
        } else {
            onPresent(.locations)
        }
    }

    private func transitNeedsReview(_ field: TransitReviewField) -> Bool {
        entry.transitDetails?.review(for: field) != nil
    }

    private func placeNeedsReview(_ field: PlaceVisitReviewField) -> Bool {
        entry.placeVisitDetails?.review(for: field) != nil
    }

    private var mapNeedsReview: Bool {
        switch entry.kind {
        case .transit:
            return transitNeedsReview(.origin)
                || transitNeedsReview(.destination)
        case .placeVisit:
            return placeNeedsReview(.place)
        case .workout:
            guard let details = entry.workoutDetails else { return false }
            return !details.fieldReviews.isEmpty
        case .wakeUp:
            return false
        }
    }

    private var startLocation: Location? {
        switch entry.kind {
        case .transit:
            entry.transitDetails?.originLocation
                ?? entry.transitDetails?.originPlace?.location
        case .placeVisit:
            entry.placeVisitDetails?.location
                ?? entry.placeVisitDetails?.place?.location
        case .workout:
            entry.workoutDetails?.movementKind == .moving
                ? entry.workoutDetails?.originLocation
                : entry.workoutDetails?.sourceLocation
                    ?? entry.workoutDetails?.place?.location
        case .wakeUp:
            nil
        }
    }

    private var endLocation: Location? {
        switch entry.kind {
        case .transit:
            entry.transitDetails?.destinationLocation
                ?? entry.transitDetails?.destinationPlace?.location
        case .placeVisit:
            entry.placeVisitDetails?.location
                ?? entry.placeVisitDetails?.place?.location
        case .workout:
            entry.workoutDetails?.movementKind == .moving
                ? entry.workoutDetails?.destinationLocation
                : entry.workoutDetails?.sourceLocation
                    ?? entry.workoutDetails?.place?.location
        case .wakeUp:
            nil
        }
    }

    private var startPlaceSymbol: PlaceSystemImage? {
        let savedSymbol: PlaceSystemImage? =
            switch entry.kind {
            case .transit: entry.transitDetails?.originPlace?.systemImage
            case .placeVisit: entry.placeVisitDetails?.place?.systemImage
            case .workout:
                entry.workoutDetails?.movementKind == .moving
                    ? entry.workoutDetails?.originPlace?.systemImage
                    : entry.workoutDetails?.place?.systemImage
            case .wakeUp: nil
            }
        return savedSymbol ?? (startLocation == nil ? nil : .mappin)
    }

    private var endPlaceSymbol: PlaceSystemImage? {
        let savedSymbol: PlaceSystemImage? =
            switch entry.kind {
            case .transit: entry.transitDetails?.destinationPlace?.systemImage
            case .placeVisit: entry.placeVisitDetails?.place?.systemImage
            case .workout:
                entry.workoutDetails?.movementKind == .moving
                    ? entry.workoutDetails?.destinationPlace?.systemImage
                    : entry.workoutDetails?.place?.systemImage
            case .wakeUp: nil
            }
        return savedSymbol ?? (endLocation == nil ? nil : .mappin)
    }
}

extension LogKind {
    fileprivate var detailTitle: LocalizedStringResource {
        switch self {
        case .transit: "Transit"
        case .placeVisit: "Place"
        case .workout: "Workout"
        case .wakeUp: "Wake Up"
        }
    }
}
