import Observation
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
    let onSubmit: () -> Bool

    @FocusState private var isFocused: Bool
    @State private var addPersonRequest: GuidedComposerPersonRequest?
    @State private var addPlaceRequest: GuidedComposerPlaceRequest?
    @State private var composerHeight: CGFloat = 52

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                HomeComposerAddMenu(
                    isDisabled: model.isSaving,
                    onSelect: onPresentSheet
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
                    GuidedComposerSuggestionPanel(
                        model: model,
                        onSavePlace: presentPlaceEditor
                    )
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
        .sheet(
            item: $addPersonRequest,
            onDismiss: {
                model.cancelPendingPersonAddition()
                isFocused = true
            }
        ) { request in
            AddPersonSheet(initialName: request.name) { person in
                model.personWasAdded(person)
                isFocused = true
            }
        }
        .sheet(
            item: $addPlaceRequest,
            onDismiss: { isFocused = true }
        ) { request in
            AddPlaceSheet(
                initialName: request.candidate.displayName,
                initialLocation: request.candidate.location,
                initialSymbol: request.candidate.systemImage,
                capturesCurrentLocation: false
            )
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

    private func presentPlaceEditor(
        for candidate: ComposerLocationCandidate
    ) {
        isFocused = false
        addPlaceRequest = GuidedComposerPlaceRequest(candidate: candidate)
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

struct GuidedComposerSuggestionPanel: View {
    let model: GuidedEntryComposerModel
    let onSavePlace: (ComposerLocationCandidate) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if case .time(let role) = model.activeSlot {
                GuidedComposerTimePicker(model: model, role: role)
                Divider()
                    .padding(.horizontal, 6)
            }

            GuidedComposerSuggestionList(
                model: model,
                onSavePlace: onSavePlace
            )

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
        .padding(.horizontal, 8)
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct GuidedComposerSuggestionList: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let model: GuidedEntryComposerModel
    let onSavePlace: (ComposerLocationCandidate) -> Void

    @Namespace private var selectionNamespace
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var hapticTrigger = 0
    @State private var scrollContentHeight: CGFloat = 220
    @State private var selectionOpacity = 1.0

    private static let coordinateSpace = "guided-composer-suggestions"

    private var scrollThreshold: Int {
        if case .time = model.activeSlot { 2 } else { 6 }
    }

    private var maximumHeight: CGFloat {
        if case .time = model.activeSlot { 160 } else { 220 }
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.suggestions.count > scrollThreshold {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.suggestions) { suggestion in
                            GuidedComposerSuggestionButton(
                                suggestion: suggestion,
                                isActive:
                                    suggestion.id
                                    == model.activeSuggestionID,
                                selectionOpacity: selectionOpacity,
                                selectionNamespace: selectionNamespace,
                                onSelect: { model.accept(suggestion) },
                                onSavePlace: onSavePlace
                            )
                        }
                    }
                    .padding(.vertical, 8)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        guard height > 0,
                            scrollContentHeight != height
                        else {
                            return
                        }
                        scrollContentHeight = height
                    }
                }
                .frame(height: min(scrollContentHeight, maximumHeight))
                .scrollBounceBehavior(.basedOnSize)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.suggestions) { suggestion in
                        GuidedComposerSuggestionButton(
                            suggestion: suggestion,
                            isActive:
                                suggestion.id == model.activeSuggestionID,
                            selectionOpacity: selectionOpacity,
                            selectionNamespace: selectionNamespace,
                            onSelect: { model.accept(suggestion) },
                            onSavePlace: onSavePlace
                        )
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .named(Self.coordinateSpace))
                        } action: { frame in
                            guard rowFrames[suggestion.id] != frame else {
                                return
                            }
                            rowFrames[suggestion.id] = frame
                        }
                    }
                }
                .padding(.vertical, 8)
                .coordinateSpace(name: Self.coordinateSpace)
                .contentShape(.rect)
                .highPriorityGesture(
                    DragGesture(
                        minimumDistance: 4,
                        coordinateSpace: .named(Self.coordinateSpace)
                    )
                    .onChanged { value in
                        selectionOpacity = 1
                        guard
                            let suggestionID = suggestionID(
                                at: value.location
                            )
                        else {
                            return
                        }
                        activate(suggestionID)
                    }
                    .onEnded { value in
                        guard
                            let suggestionID = suggestionID(
                                at: value.location
                            ),
                            let suggestion = model.suggestions.first(
                                where: { $0.id == suggestionID }
                            )
                        else {
                            var transaction = Transaction(animation: nil)
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                selectionOpacity = 0
                                model.activateFirstSuggestion()
                            }
                            withAnimation(
                                reduceMotion
                                    ? nil
                                    : .easeOut(duration: 0.08)
                            ) {
                                selectionOpacity = 1
                            }
                            return
                        }
                        activate(suggestionID)
                        model.accept(suggestion)
                    }
                )
                .sensoryFeedback(.selection, trigger: hapticTrigger)
                .animation(
                    reduceMotion ? nil : .snappy(duration: 0.2),
                    value: model.activeSuggestionID
                )
            }
        }
        .onChange(
            of: model.suggestions.map(\.id),
            initial: true
        ) { _, ids in
            if ids.count > scrollThreshold {
                model.activateFirstSuggestion()
            } else {
                let visibleIDs = Set(ids)
                rowFrames = rowFrames.filter { visibleIDs.contains($0.key) }
            }
        }
    }

    private func suggestionID(at location: CGPoint) -> String? {
        let rows = model.suggestions.compactMap { suggestion in
            rowFrames[suggestion.id].map {
                (suggestion.id, $0)
            }
        }
        guard rows.contains(where: { $0.1.contains(location) }) else {
            return nil
        }
        return rows.min {
            abs($0.1.midY - location.y) < abs($1.1.midY - location.y)
        }?.0
    }

    private func activate(_ suggestionID: String) {
        guard model.activeSuggestionID != suggestionID else { return }
        model.activateSuggestion(suggestionID)
        hapticTrigger &+= 1
    }
}

private struct GuidedComposerSuggestionButton: View {
    let suggestion: ComposerSuggestion
    let isActive: Bool
    let selectionOpacity: Double
    let selectionNamespace: Namespace.ID
    let onSelect: () -> Void
    let onSavePlace: (ComposerLocationCandidate) -> Void

    var body: some View {
        let subtitle = suggestion.subtitle.flatMap { subtitle in
            subtitle.localizedCaseInsensitiveCompare(suggestion.title)
                == .orderedSame ? nil : subtitle
        }

        Button(action: onSelect) {
            HStack(spacing: 10) {
                Group {
                    switch iconStyle {
                    case .transit(let presentation):
                        TransitPresentationIcon(
                            presentation: presentation,
                            size: 14,
                            weight: .semibold
                        )
                        .foregroundStyle(presentation.foregroundColor)
                        .frame(width: 24, height: 24)
                        .background(presentation.color.gradient, in: .circle)
                    case .place(let symbol):
                        Image(systemName: suggestion.systemImage)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(
                                symbol.primary,
                                symbol.secondary,
                                symbol.tertiary
                            )
                    case .color(let color):
                        Image(systemName: suggestion.systemImage)
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(color)
                    }
                }
                .font(.callout.weight(.medium))
                .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.title)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if subtitle != nil || suggestion.referencesTimelineBoundary {
                        detailText(subtitle: subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(
                .vertical,
                subtitle == nil && !suggestion.referencesTimelineBoundary ? 9 : 7
            )
            .contentShape(.rect)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(.primary.opacity(0.3))
                        .overlay(alignment: .trailing) {
                            Image(systemName: "return")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.trailing, 10)
                                .accessibilityHidden(true)
                        }
                        .matchedGeometryEffect(
                            id: "active-suggestion",
                            in: selectionNamespace
                        )
                        .opacity(selectionOpacity)
                }
            }
        }
        .buttonStyle(
            GuidedComposerSuggestionButtonStyle(isActive: isActive)
        )
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityHint(
            isActive ? "Selected autocomplete result" : "Autocomplete result"
        )
        .contextMenu {
            if let candidate = unsavedLocationCandidate {
                Button {
                    onSavePlace(candidate)
                } label: {
                    Label("Save Place…", systemImage: "bookmark")
                }
            }
        }
    }

    private func detailText(subtitle: String?) -> Text {
        if suggestion.referencesTimelineBoundary, let subtitle {
            return Text(
                "\(subtitle)  •  \(Image(systemName: "link.badge.plus")) Link"
            )
        }
        if suggestion.referencesTimelineBoundary {
            return Text("\(Image(systemName: "link.badge.plus")) Link")
        }
        return Text(subtitle ?? "")
    }

    private var unsavedLocationCandidate: ComposerLocationCandidate? {
        guard case .value(let tokens, _) = suggestion.kind else {
            return nil
        }
        let locations = tokens.compactMap { token in
            if case .location(let candidate, _) = token.value {
                candidate
            } else {
                nil
            }
        }
        guard locations.count == 1,
            let candidate = locations.first,
            candidate.savedPlaceID == nil
        else {
            return nil
        }
        return candidate
    }

    private var iconStyle: IconStyle {
        switch suggestion.kind {
        case .addPerson:
            return .color(.blue)
        case .semanticSplit:
            return .color(.secondary)
        case .macro(let tokens, _):
            if let leading = tokens.first(where: {
                if case .leading = $0.value { true } else { false }
            }) {
                return style(for: leading)
            }
            let values = tokens.filter {
                if case .connector = $0.value { false } else { true }
            }
            if !values.isEmpty,
                values.allSatisfy({ token in
                    switch token.value {
                    case .time, .duration: true
                    default: false
                    }
                })
            {
                return .color(.orange)
            }
            return .color(.primary)
        case .value(let tokens, _):
            return tokens.first.map(style(for:)) ?? .color(.primary)
        }
    }

    private func style(for token: ComposerToken) -> IconStyle {
        switch token.value {
        case .leading(.transit(let canonicalName)):
            .transit(
                TransitPresentationCatalog.presentation(for: canonicalName)
            )
        case .leading(.placeVisit):
            .color(.indigo)
        case .location(let location, _):
            .place(PlaceSymbols.symbol(for: location.systemImage))
        case .time, .duration:
            .color(.orange)
        case .person:
            .color(.blue)
        case .connector:
            .color(.secondary)
        }
    }

    private enum IconStyle {
        case transit(TransitPresentation)
        case place(PlaceSymbol)
        case color(Color)
    }
}

private struct GuidedComposerSuggestionButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.secondary.opacity(0.16))
                    .opacity(configuration.isPressed && !isActive ? 1 : 0)
            }
            .animation(
                .easeOut(duration: 0.06),
                value: configuration.isPressed
            )
    }
}

private struct GuidedComposerTimePicker: View {
    private static let wheelHeight: CGFloat = 180
    private static let wheelWidth: CGFloat = 300
    private static let wheelScale: CGFloat = 0.6

    let model: GuidedEntryComposerModel
    let role: ComposerTimeRole

    @State private var date = Date.now

    var body: some View {
        let suggestedDate = model.suggestedPickerDate(for: role)
        let timeZone = model.pickerTimeZone(for: role)

        HStack(spacing: 6) {
            ZStack {
                DatePicker(
                    selection: $date,
                    displayedComponents: .date
                ) {
                    if role == .start {
                        Text("Start date")
                    } else {
                        Text("End date")
                    }
                }
                .labelsHidden()
                .datePickerStyle(.compact)
                .controlSize(.mini)
                .fixedSize()
                .frame(width: 65, height: 32)
                .contentShape(.capsule)
                .clipShape(.capsule)

                Text(
                    date,
                    format: .dateTime.day().month(.abbreviated)
                )
                .frame(width: 68, height: 32)
                .background(
                    Color(uiColor: .systemGray5),
                    in: Capsule()
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .frame(width: 68, height: 44)
            .clipped()

            DatePicker(
                selection: $date,
                displayedComponents: .hourAndMinute
            ) {
                if role == .start {
                    Text("Start")
                } else {
                    Text("End")
                }
            }
            .labelsHidden()
            .datePickerStyle(.wheel)
            .frame(
                width: Self.wheelWidth,
                height: Self.wheelHeight
            )
            .scaleEffect(Self.wheelScale)
            .frame(
                width: Self.wheelWidth * Self.wheelScale,
                height: Self.wheelHeight * Self.wheelScale
            )
            .clipped()

            Button {
                model.selectTime(date, role: role)
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .environment(\.timeZone, timeZone)
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

private struct GuidedComposerPlaceRequest: Identifiable {
    let candidate: ComposerLocationCandidate

    var id: String { candidate.id }
}
