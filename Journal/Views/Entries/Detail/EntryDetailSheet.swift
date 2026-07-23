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
  @Query private var allEntries: [LogEntry]
  @Query(sort: \TransitType.canonicalName) private var transitTypes: [TransitType]

  let entry: LogEntry

  @State private var coordinator: EntryDetailCoordinator
  @State private var routeModel = WorkoutRouteModel()
  @State private var isDeleteConfirmationPresented = false
  @State private var contentIsScrolled = false
  @State private var chromeHeight: CGFloat = 0
  @State private var peopleSearchText = ""

  init(entry: LogEntry) {
    self.entry = entry
    _coordinator = State(initialValue: EntryDetailCoordinator(entry: entry))
  }

  var body: some View {
    DynamicSheet(sizing: sheetSizing) {
      ZStack(alignment: .top) {
        routeContent
          .id(coordinator.route.id)
          .transition(
            .blurReplace(
              coordinator.movesForward ? .upUp : .downUp
            )
          )

        VStack(spacing: 0) {
          DynamicSheetHeader(
            title: headerTitle,
            isElevated: contentIsScrolled
          ) {
            if coordinator.route == .details {
              Button(action: { dismiss() }) {
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
            if coordinator.route == .details,
               entry.entryKindReviewReason != nil {
              Button(action: { coordinator.present(.entryKind) }) {
                EntryDetailReviewBadge()
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

                Button(action: saveCurrentRoute) {
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

          if coordinator.route == .people {
            EntryDetailPeopleSearchField(text: $peopleSearchText)
              .padding(.horizontal, 16)
              .padding(.bottom, 8)
          }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
          proxy.size.height
        } action: { chromeHeight = $0 }
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
    .onChange(of: coordinator.route) {
      contentIsScrolled = false
      if coordinator.route != .people {
        peopleSearchText = ""
      }
    }
  }

  private var sheetSizing: DynamicSheetSizing {
    coordinator.route == .people ? .expanded : .content
  }

  private var headerTitle: LocalizedStringResource {
    coordinator.route == .details
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
        onDelete: { isDeleteConfirmationPresented = true }
      )
    case .time:
      editorViewport {
        EntryDetailTimeEditor(session: coordinator.session)
      }
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
    DynamicSheetScrollView(
      topContentInset: chromeHeight,
      isScrolled: $contentIsScrolled
    ) {
      content()
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }
  }

  private var peopleUsageCounts: [UUID: Int] {
    EntryDetailPeopleUsage.counts(in: allEntries)
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
