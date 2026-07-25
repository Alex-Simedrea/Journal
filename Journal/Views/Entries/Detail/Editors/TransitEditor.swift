import SwiftUI

struct EntryDetailTransitEditor: View {
    @Bindable var session: EntryDetailEditSession
    let transitTypes: [TransitType]
    let topContentInset: CGFloat
    @Binding var isScrolled: Bool

    var body: some View {
        DynamicSheetScrollView(
            fillsAvailableHeight: true,
            topContentInset: topContentInset,
            isScrolled: $isScrolled
        ) {
            EntryDetailTransitEditorContent(
                session: session,
                transitTypes: transitTypes
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
    }
}

struct EntryDetailTransitEditorContent: View {
    @Bindable var session: EntryDetailEditSession
    let transitTypes: [TransitType]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EntryDetailTransitTypeGrid(
                choices: EntryDetailTransitTypeProjection.choices(
                    availableNames: transitTypes.map(\.canonicalName),
                    selectedName: session.transitType
                ),
                selection: $session.transitType
            )

            LabeledTextField(
                title: "Operator or issuer",
                prompt: "Enter operator or issuer",
                text: $session.transitOperator,
                capitalization: .words
            )

            LabeledTextField(
                title: "Service identifier",
                prompt: "Enter service identifier",
                text: $session.transitServiceIdentifier,
                capitalization: .characters
            )
        }
    }
}

struct EntryDetailTransitTypeGrid: View {
    let choices: [EntryDetailTransitTypeProjection.Choice]
    @Binding var selection: String

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 4
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transit type")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(choices) { choice in
                    EntryDetailTransitTypeButton(
                        name: choice.name,
                        selected: EntryDetailTransitTypeProjection.matches(
                            choice.name,
                            selection
                        ),
                        onSelect: { selection = choice.name }
                    )
                }
            }
        }
    }
}

struct EntryDetailTransitTypeButton: View {
    let name: String
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        let presentation = TransitPresentationCatalog.presentation(for: name)

        Button(action: onSelect) {
            VStack(spacing: 6) {
                TransitPresentationIcon(
                    presentation: presentation,
                    size: 28,
                    weight: .semibold
                )

                Text(name)
                    .font(.caption2.bold())
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fill)
            .foregroundStyle(presentation.foregroundColor)
            .background(
                presentation.color,
                in: .rect(cornerRadius: 16)
            )
            .contentShape(.rect(cornerRadius: 16))
            .padding(5)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(.primary, lineWidth: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

@MainActor
enum EntryDetailTransitTypeProjection {
    struct Choice: Identifiable, Equatable {
        let name: String
        let id: String

        init(name: String) {
            self.name = name
            id = EntryDetailTransitTypeProjection.normalized(name)
        }
    }

    static let curatedNames = [
        "Walk", "Bicycle", "Scooter", "Motorcycle",
        "Car", "Taxi", "Ride share", "Uber",
        "Bolt", "Lyft", "Bus", "Train",
        "Metro", "Tram", "Ferry", "Flight",
    ]

    static func choices(
        availableNames: [String],
        selectedName: String
    ) -> [Choice] {
        var namesByKey: [String: String] = [:]

        for name in availableNames {
            insert(name, into: &namesByKey)
        }
        insert(selectedName, into: &namesByKey)

        return namesByKey.values
            .sorted(by: precedes)
            .map(Choice.init)
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        normalized(lhs) == normalized(rhs)
    }

    private static let curatedRank = Dictionary(
        uniqueKeysWithValues: curatedNames.enumerated().map {
            (normalized($0.element), $0.offset)
        }
    )

    private static func insert(
        _ name: String,
        into namesByKey: inout [String: String]
    ) {
        let trimmedName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedName.isEmpty else { return }
        let key = normalized(trimmedName)
        if namesByKey[key] == nil {
            namesByKey[key] = trimmedName
        }
    }

    private static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        let lhsRank = curatedRank[normalized(lhs)]
        let rhsRank = curatedRank[normalized(rhs)]

        switch (lhsRank, rhsRank) {
        case (let lhsRank?, let rhsRank?):
            return lhsRank < rhsRank
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#if DEBUG
    @MainActor
    private struct EntryDetailTransitEditorPreview: View {
        @State private var session: EntryDetailEditSession
        @State private var isScrolled = false
        private let transitTypes: [TransitType]

        init(selectedType: String) {
            let entry = LogEntry(kind: .transit, needsReview: false)
            entry.transitDetails = TransitDetails(
                type: selectedType,
                sourceOrganizationName: "CFR Călători",
                sourceServiceIdentifier: "IC536"
            )
            _session = State(initialValue: EntryDetailEditSession(entry: entry))
            transitTypes = EntryDetailTransitTypeProjection.curatedNames.map {
                TransitType(canonicalName: $0, aliases: [])
            }
        }

        var body: some View {
            EntryDetailTransitEditor(
                session: session,
                transitTypes: transitTypes,
                topContentInset: 0,
                isScrolled: $isScrolled
            )
            .background(.regularMaterial)
        }
    }

    #Preview("Transit editor · Light") {
        EntryDetailTransitEditorPreview(selectedType: "Ride share")
            .environment(\.colorScheme, .light)
    }

    #Preview("Transit editor · Dark") {
        EntryDetailTransitEditorPreview(selectedType: "Uber")
            .environment(\.colorScheme, .dark)
    }
#endif
