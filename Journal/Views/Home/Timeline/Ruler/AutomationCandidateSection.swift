import SwiftUI

struct TimelineAutomationCandidateSection: View {
    let candidates: [AutomationCandidateSnapshot]
    let onSelect: (AutomationCandidateSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Detected Entries", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(candidates) { candidate in
                TimelineAutomationCandidateTile(
                    candidate: candidate,
                    onSelect: { onSelect(candidate) }
                )
            }
        }
        .padding(.horizontal)
        .padding(.top, 28)
    }
}

private struct TimelineAutomationCandidateTile: View {
    let candidate: AutomationCandidateSnapshot
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(
                    systemName: candidate.kind == .visit
                        ? "mappin.and.ellipse"
                        : "arrow.triangle.swap"
                )
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(.orange.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        Text(
                            candidate.startTime,
                            format: .dateTime.hour().minute()
                        )
                        .environment(
                            \.timeZone,
                            TimeZone(
                                identifier: candidate.timeZoneIdentifier
                            ) ?? .current
                        )
                        Text("–")
                        Text(
                            candidate.endTime,
                            format: .dateTime.hour().minute()
                        )
                        .environment(
                            \.timeZone,
                            TimeZone(
                                identifier: candidate.endTimeZoneIdentifier
                            ) ?? .current
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                ReviewBadge(size: 17)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.background, in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        switch candidate.kind {
        case .visit: candidate.visitName
        case .transit: candidate.motionKind?.transitTypeName ?? "Transit"
        }
    }

    private var subtitle: String {
        switch candidate.kind {
        case .visit:
            String(localized: "Detected visit")
        case .transit:
            String(
                localized: "\(candidate.originName) to \(candidate.destinationName)"
            )
        }
    }
}
