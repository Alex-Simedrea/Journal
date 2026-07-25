//
//  TimeZoneEditor.swift
//  Journal
//

import SwiftUI

struct TimeZoneChoice: Identifiable, Equatable {
    let identifier: String
    let city: String
    let region: String

    var id: String { identifier }
}

struct TimeZoneChoiceSection: Identifiable, Equatable {
    let region: String
    let choices: [TimeZoneChoice]

    var id: String { region }
}

enum TimeZoneCatalog {
    static let all: [TimeZoneChoice] = {
        var seen = Set<String>()
        return TimeZone.knownTimeZoneIdentifiers.compactMap { identifier in
            guard seen.insert(identifier).inserted else { return nil }
            let components = identifier.split(separator: "/").map(String.init)
            let city = (components.last ?? identifier)
                .replacingOccurrences(of: "_", with: " ")
            let region = components.dropLast()
                .joined(separator: " · ")
                .replacingOccurrences(of: "_", with: " ")
            return TimeZoneChoice(
                identifier: identifier,
                city: city,
                region: region.isEmpty ? "Other" : region
            )
        }
        .sorted {
            let regionOrder = $0.region.localizedStandardCompare($1.region)
            return regionOrder == .orderedSame
                ? $0.city.localizedStandardCompare($1.city) == .orderedAscending
                : regionOrder == .orderedAscending
        }
    }()

    static func filtered(by query: String) -> [TimeZoneChoice] {
        let query = normalized(query)
        guard !query.isEmpty else { return all }
        return all.filter {
            normalized("\($0.city) \($0.region) \($0.identifier)").contains(query)
        }
    }

    static func title(for identifier: String) -> String {
        all.first(where: { $0.identifier == identifier })?.city
            ?? identifier.replacingOccurrences(of: "_", with: " ")
    }

    static func detail(for identifier: String, date: Date) -> String {
        guard let timeZone = TimeZone(identifier: identifier) else {
            return identifier
        }
        let offset = timeZone.secondsFromGMT(for: date)
        let sign = offset >= 0 ? "+" : "−"
        let absoluteMinutes = abs(offset) / 60
        let hours = absoluteMinutes / 60
        let minutes = absoluteMinutes % 60
        let offsetText = minutes == 0
            ? "GMT\(sign)\(hours)"
            : "GMT\(sign)\(hours):\(String(format: "%02d", minutes))"

        guard let abbreviation = timeZone.abbreviation(for: date) else {
            return offsetText
        }
        if abbreviation.uppercased().hasPrefix("GMT") {
            return abbreviation
        }
        return "\(abbreviation) · \(offsetText)"
    }

    static func sections(filteredBy query: String) -> [TimeZoneChoiceSection] {
        Dictionary(grouping: filtered(by: query), by: \.region)
            .map { TimeZoneChoiceSection(region: $0.key, choices: $0.value) }
            .sorted {
                $0.region.localizedStandardCompare($1.region) == .orderedAscending
            }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        .replacingOccurrences(of: "_", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TimeZoneEditor: View {
    @Binding var selection: String
    @Binding var searchText: String
    @Binding var isScrolled: Bool
    let date: Date
    let topContentInset: CGFloat

    var body: some View {
        DynamicSheetScrollView(
            fillsAvailableHeight: true,
            topContentInset: topContentInset,
            isScrolled: $isScrolled
        ) {
            TimeZoneResults(
                sections: TimeZoneCatalog.sections(filteredBy: searchText),
                searchText: searchText,
                selection: $selection,
                date: date
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }
}

private struct TimeZoneResults: View {
    let sections: [TimeZoneChoiceSection]
    let searchText: String
    @Binding var selection: String
    let date: Date

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            if sections.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                ForEach(sections) { section in
                    TimeZoneSectionView(
                        section: section,
                        selection: $selection,
                        date: date
                    )
                }
            }
        }
    }
}

private struct TimeZoneSectionView: View {
    let section: TimeZoneChoiceSection
    @Binding var selection: String
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.region)
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(section.choices) { choice in
                    TimeZoneSectionRow(
                        choice: choice,
                        showsDivider: choice.id != section.choices.first?.id,
                        selection: $selection,
                        date: date
                    )
                }
            }
            .dynamicSheetSurface()
        }
    }
}

private struct TimeZoneSectionRow: View {
    let choice: TimeZoneChoice
    let showsDivider: Bool
    @Binding var selection: String
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider {
                Divider()
                    .padding(.leading, 52)
            }

            TimeZoneChoiceButton(
                choice: choice,
                isSelected: selection == choice.identifier,
                date: date,
                onSelect: { selection = choice.identifier }
            )
        }
    }
}

private struct TimeZoneChoiceButton: View {
    let choice: TimeZoneChoice
    let isSelected: Bool
    let date: Date
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.city)
                        .foregroundStyle(.primary)
                    Text(TimeZoneCatalog.detail(for: choice.identifier, date: date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .font(.title3)
                }
            }
            .contentShape(.rect)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(choice.city), \(choice.region)")
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Time Zones – Dark") {
    @Previewable @State var selection = "Europe/Bucharest"
    @Previewable @State var searchText = ""
    @Previewable @State var isScrolled = false

    TimeZoneEditor(
        selection: $selection,
        searchText: $searchText,
        isScrolled: $isScrolled,
        date: .now,
        topContentInset: 0
    )
    .preferredColorScheme(.dark)
    .background(Color(uiColor: .systemGroupedBackground))
}
