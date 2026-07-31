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

    @State private var legacyModel = EntryComposerModel()
    @State private var guidedModel = GuidedEntryComposerModel()
    @State private var mode = GuidedComposerMode.guided
    @State private var presentedSheet: HomeComposerSheet?

    var body: some View {
        HomeComposerModeContent(
            mode: mode,
            legacyModel: legacyModel,
            guidedModel: guidedModel,
            places: places,
            people: people,
            transitTypes: transitTypes,
            selectedDay: selectedDay,
            guidedContextRevision: guidedContextRevision,
            onPresentSheet: { presentedSheet = $0 },
            onToggleMode: toggleMode,
            onLegacySubmit: submitLegacy,
            onGuidedSubmit: submitGuided
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

    private func submitLegacy() async -> Bool {
        let saved = await legacyModel.submit(
            places: places,
            people: people,
            transitTypes: transitTypes,
            selectedDay: selectedDay,
            modelContext: modelContext
        )
        guard saved else { return false }

        legacyModel.input = ""
        onEntryChanged()
        return true
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

    private func toggleMode() {
        guard !legacyModel.isSaving, !guidedModel.isSaving else { return }
        mode = mode == .guided ? .legacyAI : .guided
    }
}

enum HomeComposerSheet: String, Identifiable {
    case manualTransit
    case manualVisit
    case newPlace
    case newPerson

    var id: String { rawValue }
}

private struct HomeComposerModeContent: View {
    let mode: GuidedComposerMode
    let legacyModel: EntryComposerModel
    let guidedModel: GuidedEntryComposerModel
    let places: [Place]
    let people: [Person]
    let transitTypes: [TransitType]
    let selectedDay: TimelineDayKey
    let guidedContextRevision: GuidedComposerContextRevision
    let onPresentSheet: (HomeComposerSheet) -> Void
    let onToggleMode: () -> Void
    let onLegacySubmit: () async -> Bool
    let onGuidedSubmit: () -> Bool

    var body: some View {
        switch mode {
        case .guided:
            HomeGuidedEntryComposer(
                model: guidedModel,
                places: places,
                people: people,
                transitTypes: transitTypes,
                selectedDay: selectedDay,
                contextRevision: guidedContextRevision,
                onPresentSheet: onPresentSheet,
                onToggleMode: onToggleMode,
                onSubmit: onGuidedSubmit
            )
        case .legacyAI:
            HomeLegacyComposerInput(
                model: legacyModel,
                onPresentSheet: onPresentSheet,
                onToggleMode: onToggleMode,
                onSubmit: onLegacySubmit
            )
        }
    }
}

private struct HomeLegacyComposerInput: View {
    @Bindable var model: EntryComposerModel
    let onPresentSheet: (HomeComposerSheet) -> Void
    let onToggleMode: () -> Void
    let onSubmit: () async -> Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                HomeComposerAddMenu(
                    isDisabled: model.isSaving,
                    mode: .legacyAI,
                    onSelect: onPresentSheet,
                    onToggleMode: onToggleMode
                )

                HStack(alignment: .bottom, spacing: 4) {
                    TextField(
                        "Describe an entry",
                        text: $model.input,
                        axis: .vertical
                    )
                    .focused($isFocused)
                    .lineLimit(1...5)
                    .frame(minHeight: 36, alignment: .center)
                    .submitLabel(.send)
                    .disabled(model.isSaving)
                    .onSubmit(submit)

                    HomeComposerSendButton(
                        isLoading: model.isSaving,
                        isEnabled: model.canSubmit,
                        action: submit
                    )
                }
                .padding(.leading, 16)
                .padding(.trailing, 4)
                .padding(.vertical, 4)
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(
                        cornerRadius: 22,
                        style: .continuous
                    )
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .alert("Couldn’t Log Entry", isPresented: $model.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "An unknown error occurred.")
        }
    }

    private func submit() {
        guard model.canSubmit else { return }
        isFocused = false
        Task {
            _ = await onSubmit()
            isFocused = false
        }
    }
}

struct HomeComposerAddMenu: View {
    let isDisabled: Bool
    let mode: GuidedComposerMode
    let onSelect: (HomeComposerSheet) -> Void
    let onToggleMode: () -> Void

    var body: some View {
        Menu {
            Section("Composer") {
                Button(action: onToggleMode) {
                    Label(
                        mode == .guided
                            ? "Use AI Composer"
                            : "Use Guided Composer",
                        systemImage: mode == .guided
                            ? "sparkles"
                            : "text.badge.checkmark"
                    )
                }
            }

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
