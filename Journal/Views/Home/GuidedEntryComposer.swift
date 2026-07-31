import SwiftData
import SwiftUI

struct HomeGuidedEntryComposer: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var model: GuidedEntryComposerModel
    let places: [Place]
    let people: [Person]
    let transitTypes: [TransitType]
    let selectedDay: TimelineDayKey
    let contextRevision: GuidedComposerContextRevision
    let onPresentSheet: (HomeComposerSheet) -> Void
    let onToggleMode: () -> Void
    let onSubmit: () -> Bool

    @FocusState private var isFocused: Bool
    @State private var addPersonRequest: GuidedComposerPersonRequest?
    @State private var composerHeight: CGFloat = 52

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                HomeComposerAddMenu(
                    isDisabled: model.isSaving,
                    mode: .guided,
                    onSelect: onPresentSheet,
                    onToggleMode: onToggleMode
                )

                GuidedComposerEditor(
                    model: model,
                    isFocused: $isFocused,
                    onSubmit: submit
                )
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: {
                composerHeight = $0
            }
            .overlay(alignment: .bottomTrailing) {
                if model.shouldPresentSuggestions {
                    GuidedComposerSuggestionPanel(model: model)
                        .padding(.leading, 52)
                        .offset(y: -(composerHeight + 8))
                        .transition(
                            .move(edge: .bottom).combined(with: .opacity)
                        )
                        .zIndex(1)
                }
            }
            .animation(
                .snappy(duration: 0.18),
                value: model.shouldPresentSuggestions
            )
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .task(id: contextRevision) {
            model.prepare(
                selectedDay: selectedDay,
                places: places,
                people: people,
                transitTypes: transitTypes,
                contextRevision: contextRevision,
                modelContext: modelContext
            )
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            model.appBecameActive()
        }
        .onChange(of: model.pendingPersonName) { _, name in
            guard let name else { return }
            addPersonRequest = GuidedComposerPersonRequest(name: name)
        }
        .onChange(of: isFocused) { _, isFocused in
            model.editorFocusDidChange(isFocused)
        }
        .sheet(item: $addPersonRequest, onDismiss: {
            model.cancelPendingPersonAddition()
            isFocused = true
        }) { request in
            AddPersonSheet(initialName: request.name) { person in
                model.personWasAdded(person)
                isFocused = true
            }
        }
        .alert("Couldn’t Log Entry", isPresented: $model.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "An unknown error occurred.")
        }
    }

    private func submit() {
        guard model.canSubmit else {
            model.acceptTopSuggestion()
            return
        }
        isFocused = false
        if onSubmit() {
            isFocused = false
        }
    }
}

private struct GuidedComposerEditor: View {
    @Bindable var model: GuidedEntryComposerModel
    let isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ZStack(alignment: .topLeading) {
                Text(model.editorText)
                    .font(.body)
                    .lineLimit(1...4)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .opacity(0)
                    .accessibilityHidden(true)

                if model.isIdle {
                    Text("Describe an entry")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(
                    text: $model.editorText,
                    selection: $model.selection
                )
                .textEditorStyle(.plain)
                .scrollContentBackground(.hidden)
                .focused(isFocused)
                .frame(
                    minHeight: 36,
                    maxHeight: model.isIdle ? 36 : 104,
                    alignment: .top
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .writingToolsBehavior(.disabled)
                .accessibilityLabel("Guided entry")
                .accessibilityValue(model.accessibilityValue)
                .onChange(of: model.editorText) {
                    model.editorTextDidChange()
                }
                .onChange(of: model.selection) {
                    model.selectionDidChange()
                }
            }
            .frame(
                minHeight: 36,
                maxHeight: model.isIdle ? 36 : 104,
                alignment: .top
            )
            .clipped()

            HomeComposerSendButton(
                isLoading: model.isSaving,
                isEnabled: model.canSubmit,
                action: onSubmit
            )
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }
}

private struct GuidedComposerSuggestionPanel: View {
    let model: GuidedEntryComposerModel

    var body: some View {
        VStack(spacing: 0) {
            if case .time(let role) = model.activeSlot {
                GuidedComposerTimePicker(model: model, role: role)
                Divider()
            }

            GuidedComposerSuggestionList(model: model)

            if model.isSearchingPlaces {
                HStack(spacing: 8) {
                    Text("Searching places…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    ProgressView()
                        .controlSize(.mini)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Searching places")
            }

            if model.isCalculatingRoutes {
                HStack(spacing: 8) {
                    Text("Calculating route…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    ProgressView()
                        .controlSize(.mini)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Calculating route")
            }

            if let message = model.locationStatusMessage {
                GuidedComposerLocationStatusRow(message: message)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator.opacity(0.75), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.24), radius: 14, y: 7)
        .accessibilityElement(children: .contain)
    }
}

private struct GuidedComposerLocationStatusRow: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "location.slash")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .accessibilityLabel("Current location unavailable")
            .accessibilityValue(message)
    }
}

private struct GuidedComposerSuggestionList: View {
    let model: GuidedEntryComposerModel

    var body: some View {
        if model.suggestions.count > 6 {
            ScrollView {
                LazyVStack(spacing: 0) {
                    suggestionRows
                }
            }
            .frame(maxHeight: 320)
            .scrollBounceBehavior(.basedOnSize)
        } else {
            VStack(spacing: 0) {
                suggestionRows
            }
        }
    }

    @ViewBuilder
    private var suggestionRows: some View {
        ForEach(model.suggestions) { suggestion in
            GuidedComposerSuggestionButton(
                suggestion: suggestion,
                isPrimary: suggestion.id == model.suggestions.first?.id,
                onSelect: { model.accept(suggestion) }
            )
        }
    }
}

private struct GuidedComposerSuggestionButton: View {
    let suggestion: ComposerSuggestion
    let isPrimary: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: suggestion.systemImage)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isPrimary ? .white : .secondary)
                    .frame(width: 20)

                Text(suggestion.title)
                    .font(.callout.weight(isPrimary ? .semibold : .regular))
                    .foregroundStyle(isPrimary ? .white : .primary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                if let subtitle = visibleSubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(
                            isPrimary
                                ? Color.white.opacity(0.78)
                                : Color.secondary
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if isPrimary {
                    Image(systemName: "return")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(.rect)
            .background(
                isPrimary ? Color.accentColor : Color.clear
            )
            .overlay(alignment: .bottom) {
                if !isPrimary {
                    Divider()
                        .padding(.leading, 40)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(isPrimary ? "Top autocomplete result" : "")
    }

    private var visibleSubtitle: String? {
        guard let subtitle = suggestion.subtitle,
              subtitle.localizedCaseInsensitiveCompare(suggestion.title)
                != .orderedSame else {
            return nil
        }
        return subtitle
    }
}

private struct GuidedComposerTimePicker: View {
    let model: GuidedEntryComposerModel
    let role: ComposerTimeRole

    @State private var date = Date.now

    var body: some View {
        let suggestedDate = model.suggestedPickerDate(for: role)
        let timeZone = model.pickerTimeZone(for: role)

        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            DatePicker(
                role == .start ? "Start" : "End",
                selection: $date,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .environment(\.timeZone, timeZone)

            Spacer(minLength: 0)

            Button("Use") {
                model.selectTime(date, role: role)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .task(
            id: GuidedComposerTimePickerTaskID(
                role: role,
                contextID: model.pickerContextID(for: role)
            )
        ) {
            date = suggestedDate
        }
    }
}

private struct GuidedComposerTimePickerTaskID: Equatable {
    let role: ComposerTimeRole
    let contextID: String
}

private struct GuidedComposerPersonRequest: Identifiable {
    let id = UUID()
    let name: String
}
