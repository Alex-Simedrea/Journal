import SwiftData
import SwiftUI

struct EntrySearchScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Namespace private var dayTransition
    @State private var model = EntrySearchModel()
    @FocusState private var isSearchFocused: Bool
    @State private var presentedSheet: HomeSheet?
    @State private var presentedDay: TimelineDayKey?
    @State private var pendingEntryDeletionID: UUID?
    @State private var operationErrorMessage: String?

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            searchResults
        }
            .navigationTitle("Search")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                EntrySearchComposer(
                    text: $model.query,
                    isFocused: $isSearchFocused,
                    onTextChange: model.queryDidChange,
                    onSubmit: model.submitSearch
                )
            }
            .sheet(item: $presentedSheet, onDismiss: finishEntrySheet) { sheet in
                HomeDetailSheetContent(
                    sheet: sheet,
                    entryProvider: model.entry(withID:),
                    onRequestDelete: requestEntryDeletion
                )
            }
            .fullScreenCover(item: $presentedDay, onDismiss: reloadEntries) { day in
                EntrySearchTimelineCover(
                    initialDay: day,
                    namespace: dayTransition
                )
            }
            .alert(
                "Couldn’t Update Entry",
                isPresented: Binding(
                    get: { operationErrorMessage != nil },
                    set: { if !$0 { operationErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(operationErrorMessage ?? "An unknown error occurred.")
            }
            .task {
                model.load(in: modelContext)
                await Task.yield()
                isSearchFocused = true
            }
            .onReceive(TimelineDataChange.publisher) { _ in
                model.load(in: modelContext)
            }
    }

    @ViewBuilder private var searchResults: some View {
        if let errorMessage = model.errorMessage {
            ContentUnavailableView {
                Label("Couldn’t Search Entries", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            }
        } else if !model.hasQuery {
            ContentUnavailableView {
                Label("Search Entries", systemImage: "magnifyingglass")
            } description: {
                Text("Search by people, places, or transit types.")
            }
        } else if model.sections.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(model.sections) { section in
                        EntrySearchResultSection(
                            section: section,
                            namespace: dayTransition,
                            onOpenDay: { presentedDay = $0 },
                            onSelect: { presentedSheet = .details($0) }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func requestEntryDeletion(_ entryID: UUID) {
        pendingEntryDeletionID = entryID
        presentedSheet = nil
    }

    private func finishEntrySheet() {
        if let entryID = pendingEntryDeletionID {
            pendingEntryDeletionID = nil
            do {
                try JournalDeletionService.delete(
                    entryID: entryID,
                    in: modelContext
                )
            } catch {
                operationErrorMessage = error.localizedDescription
            }
        }
        model.load(in: modelContext)
    }

    private func reloadEntries() {
        model.load(in: modelContext)
    }
}

private struct EntrySearchResultSection: View {
    let section: EntrySearchSection
    let namespace: Namespace.ID
    let onOpenDay: (TimelineDayKey) -> Void
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                onOpenDay(section.day)
            } label: {
                Text(DaySummaryDatePresentation.dayTitle(for: section.day))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: section.day, in: namespace)
            .accessibilityHint("Opens this day’s timeline")

            ForEach(section.occurrences) { occurrence in
                TimelineEntryCard(
                    occurrence: occurrence,
                    onTap: { onSelect(occurrence.entryID) }
                )
            }
        }
    }
}

private struct EntrySearchTimelineCover: View {
    @State private var selectedDay: TimelineDayKey
    let initialDay: TimelineDayKey
    let namespace: Namespace.ID

    init(
        initialDay: TimelineDayKey,
        namespace: Namespace.ID
    ) {
        _selectedDay = State(initialValue: initialDay)
        self.initialDay = initialDay
        self.namespace = namespace
    }

    var body: some View {
        NavigationStack {
            DayTimelineScreen(selectedDay: $selectedDay)
        }
        .navigationTransition(.zoom(sourceID: initialDay, in: namespace))
    }
}

private struct EntrySearchComposer: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let onTextChange: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("People, places, or transit types", text: $text)
                .focused(isFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: text, onTextChange)
                .onSubmit {
                    onSubmit()
                    isFocused.wrappedValue = false
                }

            if !text.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") {
                    text = ""
                    isFocused.wrappedValue = true
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}
