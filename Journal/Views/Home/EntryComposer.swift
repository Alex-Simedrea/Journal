//
//  HomeEntryComposer.swift
//  Journal
//

import SwiftData
import SwiftUI

struct HomeEntryComposer: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Place.name) private var places: [Place]
    @Query(sort: \Person.name) private var people: [Person]
    @Query(sort: \TransitType.canonicalName)
    private var transitTypes: [TransitType]

    let selectedDay: TimelineDayKey
    let timelineRevision: Int
    let onEntryChanged: () -> Void

    @State private var guidedModel = GuidedEntryComposerModel()
    @State private var presentedSheet: HomeComposerSheet?

    var body: some View {
        HomeGuidedEntryComposer(
            model: guidedModel,
            places: places,
            people: people,
            transitTypes: transitTypes,
            selectedDay: selectedDay,
            contextRevision: guidedContextRevision,
            onPresentSheet: { presentedSheet = $0 },
            onSubmit: submitGuided
        )
        .sheet(item: $presentedSheet, onDismiss: onEntryChanged) { sheet in
            HomeComposerSheetContent(sheet: sheet)
        }
    }

    private var guidedContextRevision: GuidedComposerContextRevision {
        GuidedComposerContextRevision(
            selectedDay: selectedDay,
            places: places.map {
                GuidedComposerContextRevision.PlaceRevision(
                    id: $0.id,
                    name: $0.name,
                    aliases: $0.aliases,
                    location: $0.location,
                    systemImage: $0.systemImage,
                    accuracyRadiusMeters: $0.accuracyRadiusMeters
                )
            },
            people: people.map {
                GuidedComposerContextRevision.PersonRevision(
                    id: $0.id,
                    name: $0.name,
                    aliases: $0.aliases,
                    contactIdentifier: $0.contactIdentifier
                )
            },
            transitTypes: transitTypes.map {
                GuidedComposerContextRevision.TransitTypeRevision(
                    canonicalName: $0.canonicalName,
                    aliases: $0.aliases,
                    routingMode: $0.routingMode
                )
            },
            timelineRevision: timelineRevision
        )
    }

    private func submitGuided() -> Bool {
        let saved = guidedModel.submit(
            places: places,
            people: people,
            modelContext: modelContext
        )
        if saved {
            onEntryChanged()
        }
        return saved
    }
}

enum HomeComposerSheet: String, Identifiable {
    case manualTransit
    case manualVisit
    case newPlace
    case newPerson

    var id: String { rawValue }
}

struct HomeComposerAddMenu: View {
    let isDisabled: Bool
    let onSelect: (HomeComposerSheet) -> Void

    var body: some View {
        Menu {
            Section("Log Manually") {
                Button {
                    onSelect(.manualTransit)
                } label: {
                    Label("Transit", systemImage: "arrow.triangle.swap")
                }

                Button {
                    onSelect(.manualVisit)
                } label: {
                    Label("Place Visit", systemImage: "mappin.and.ellipse")
                }
            }

            Section("Library") {
                Button {
                    onSelect(.newPlace)
                } label: {
                    Label("New Place", systemImage: "mappin.circle")
                }

                Button {
                    onSelect(.newPerson)
                } label: {
                    Label("New Person", systemImage: "person.badge.plus")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .disabled(isDisabled)
        .tint(.primary)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel("Add")
    }
}

struct HomeComposerSendButton: View {
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(width: 48, height: 36)
                .accessibilityLabel("Resolving entry")
        } else {
            Button(action: action) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 32)
                    .background(
                        isEnabled
                            ? Color.accentColor
                            : Color.secondary.opacity(0.3),
                        in: Capsule()
                    )
                    .frame(width: 48, height: 36)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel("Log entry")
        }
    }
}

private struct HomeComposerSheetContent: View {
    let sheet: HomeComposerSheet

    var body: some View {
        switch sheet {
        case .manualTransit:
            TransitLogSheet()
        case .manualVisit:
            PlaceVisitLogSheet()
        case .newPlace:
            AddPlaceSheet()
        case .newPerson:
            AddPersonSheet()
        }
    }
}
