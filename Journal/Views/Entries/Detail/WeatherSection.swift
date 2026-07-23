//
//  EntryWeatherSection.swift
//  Journal
//

import SwiftData
import SwiftUI
import WeatherKit

struct EntryWeatherSection: View {
    @Environment(\.modelContext) private var modelContext

    let entry: LogEntry

    @State private var errorMessage: String?
    @State private var retryID = 0

    var body: some View {
        Section("Weather") {
            if let weather = entry.weather {
                EntryWeatherSnapshotContent(weather: weather)
            } else if EntryWeatherService.request(for: entry) == nil {
                EntryWeatherUnavailableContent()
            } else if let errorMessage {
                EntryWeatherFailureContent(
                    message: errorMessage,
                    onRetry: retry
                )
            } else {
                ProgressView("Loading weather…")
            }
        }
        .task(
            id: EntryWeatherTaskID(
                request: EntryWeatherService.request(for: entry),
                retryID: retryID
            )
        ) {
            await loadWeatherIfNeeded()
        }
    }

    private func retry() {
        errorMessage = nil
        retryID += 1
    }

    private func loadWeatherIfNeeded() async {
        guard entry.weather == nil,
              EntryWeatherService.request(for: entry) != nil else {
            return
        }

        do {
            try await EntryWeatherService.populate(
                entry,
                in: modelContext
            )
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EntryWeatherTaskID: Equatable {
    let request: EntryWeatherRequest?
    let retryID: Int
}

private struct EntryWeatherSnapshotContent: View {
    let weather: EntryWeather

    var body: some View {
        LabeledContent("Condition") {
            Label(conditionDescription, systemImage: weather.symbolName)
        }
        LabeledContent("Temperature") {
            Text(
                weather.temperature,
                format: .measurement(width: .abbreviated, usage: .weather)
            )
        }
        LabeledContent("Humidity") {
            Text(
                weather.humidity,
                format: .percent.precision(.fractionLength(0))
            )
        }
        EntryWeatherAttributionView()
    }

    private var conditionDescription: String {
        WeatherCondition(rawValue: weather.condition)?.description
            ?? weather.condition
    }
}

private struct EntryWeatherUnavailableContent: View {
    var body: some View {
        ContentUnavailableView {
            Label("Weather Unavailable", systemImage: "cloud.slash")
        } description: {
            Text("Resolve the entry’s start time and location to attach weather.")
        }
    }
}

private struct EntryWeatherFailureContent: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary)
        Button("Retry", action: onRetry)
    }
}

private struct EntryWeatherAttributionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var attribution: EntryWeatherAttribution?

    var body: some View {
        if let attribution {
            Link(destination: attribution.legalPageURL) {
                AsyncImage(
                    url: colorScheme == .dark
                        ? attribution.darkMarkURL
                        : attribution.lightMarkURL
                ) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                }
                .frame(height: 14)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel("Apple Weather attribution")
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .task { await loadAttribution() }
        }
    }

    private func loadAttribution() async {
        attribution = try? await WeatherKitEntryClient.shared.attribution()
    }
}
