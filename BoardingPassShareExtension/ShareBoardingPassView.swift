import SwiftUI

struct ShareBoardingPassView: View {
    let model: BoardingPassShareModel
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        NavigationStack {
            BoardingPassShareContent(
                phase: model.phase,
                onImport: onImport
            )
            .navigationTitle("Import Boarding Pass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: onCancel)
                }
            }
        }
    }
}

private struct BoardingPassShareContent: View {
    let phase: BoardingPassSharePhase
    let onImport: () -> Void

    var body: some View {
        VStack {
            switch phase {
            case .loading:
                BoardingPassShareLoadingView()
            case .ready(let pendingImport):
                BoardingPassSharePreview(
                    pendingImport: pendingImport,
                    isSaving: false,
                    onImport: onImport
                )
            case .saving(let pendingImport):
                BoardingPassSharePreview(
                    pendingImport: pendingImport,
                    isSaving: true,
                    onImport: onImport
                )
            case .failed(let message):
                BoardingPassShareErrorView(message: message)
            }
        }
    }
}

private struct BoardingPassShareLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Reading boarding pass…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BoardingPassSharePreview: View {
    let pendingImport: PendingBoardingPassImport
    let isSaving: Bool
    let onImport: () -> Void

    var body: some View {
        Form {
            BoardingPassShareRouteSection(pendingImport: pendingImport)
            BoardingPassShareSourceSection(pendingImport: pendingImport)

            Section {
                Button("Save for Journal", action: onImport)
                    .frame(maxWidth: .infinity)
                    .disabled(isSaving)
            } footer: {
                Text("Open Journal afterward to review the route and create the entry.")
            }
        }
    }
}

private struct BoardingPassShareRouteSection: View {
    let pendingImport: PendingBoardingPassImport

    var body: some View {
        Section("Journey") {
            LabeledContent(
                "Type",
                value: pendingImport.transitTypeName ?? "Needs review"
            )
            LabeledContent(
                "From",
                value: pendingImport.originName ?? "Needs review"
            )
            LabeledContent(
                "To",
                value: pendingImport.destinationName ?? "Needs review"
            )

            if let startTime = pendingImport.startTime {
                LabeledContent("Departure") {
                    Text(
                        startTime,
                        format: .dateTime
                            .day()
                            .month(.abbreviated)
                            .hour()
                            .minute()
                    )
                }
            }

            if let endTime = pendingImport.endTime {
                LabeledContent("Arrival") {
                    Text(
                        endTime,
                        format: .dateTime
                            .day()
                            .month(.abbreviated)
                            .hour()
                            .minute()
                    )
                }
            }
        }
    }
}

private struct BoardingPassShareSourceSection: View {
    let pendingImport: PendingBoardingPassImport

    var body: some View {
        Section("Pass") {
            if let organizationName = pendingImport.organizationName {
                LabeledContent("Issuer", value: organizationName)
            }
            if let serviceIdentifier = pendingImport.serviceIdentifier {
                LabeledContent("Service", value: serviceIdentifier)
            }
        }
    }
}

private struct BoardingPassShareErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t Read Pass", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
    }
}
