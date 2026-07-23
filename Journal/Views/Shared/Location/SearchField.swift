//
//  LocationSearchField.swift
//  Journal
//

import SwiftUI

struct LocationSearchField: View {
    let service: LocationSearchService
    let isResolving: Bool
    let onSelect: (LocationSearchSuggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(
                    "Search for an address or place",
                    text: Binding(
                        get: { service.query },
                        set: { service.query = $0 }
                    )
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

                if isResolving {
                    ProgressView()
                        .controlSize(.small)
                } else if !service.query.isEmpty {
                    Button {
                        service.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.vertical, 4)

            if !service.suggestions.isEmpty {
                Divider()
                    .padding(.top, 8)

                ForEach(service.suggestions) { suggestion in
                    Button {
                        onSelect(suggestion)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading, 36)
                }
            }

            if let errorMessage = service.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
        }
    }
}
