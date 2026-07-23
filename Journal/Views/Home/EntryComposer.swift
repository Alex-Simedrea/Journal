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
    let onEntryChanged: () -> Void

    @State private var model = EntryComposerModel()
    @State private var presentedSheet: HomeComposerSheet?

    var body: some View {
        HomeComposerInput(
            model: model,
            onPresentSheet: { presentedSheet = $0 },
            onSubmit: submit
        )
        .sheet(item: $presentedSheet, onDismiss: onEntryChanged) { sheet in
            HomeComposerSheetContent(sheet: sheet)
        }
    }

    private func submit() async -> Bool {
        let saved = await model.submit(
            places: places,
            people: people,
            transitTypes: transitTypes,
            selectedDay: selectedDay,
            modelContext: modelContext
        )
        guard saved else { return false }

        model.input = ""
        onEntryChanged()
        return true
    }
}

private enum HomeComposerSheet: String, Identifiable {
    case manualTransit
    case manualVisit
    case newPlace
    case newPerson

    var id: String { rawValue }
}

private struct HomeComposerInput: View {
    @Bindable var model: EntryComposerModel
    let onPresentSheet: (HomeComposerSheet) -> Void
    let onSubmit: () async -> Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                HomeComposerAddMenu(
                    isDisabled: model.isSaving,
                    onSelect: onPresentSheet
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

private struct HomeComposerAddMenu: View {
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

private struct HomeComposerSendButton: View {
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
