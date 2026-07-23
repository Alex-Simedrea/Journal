import MapKit
import Photos
import SwiftUI

struct EntryDetailTimeCard: View {
    let startTime: Date?
    let endTime: Date?
    let startTimeZoneIdentifier: String
    let endTimeZoneIdentifier: String
    let editable: Bool
    let needsReview: Bool
    let onEdit: () -> Void

    var body: some View {
        Button(action: editable ? onEdit : {}) {
            VStack(alignment: .leading, spacing: 1) {
                EntryDetailDateText(
                    date: startTime,
                    timeZoneIdentifier: startTimeZoneIdentifier
                )
                EntryDetailDurationRow(duration: duration)
                EntryDetailDateText(
                    date: endTime,
                    timeZoneIdentifier: endTimeZoneIdentifier
                )
            }
            .padding(.leading, 10)
            .padding(.trailing, editable ? 30 : 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(maxHeight: .infinity)
        .background(.background, in: .rect(cornerRadius: 22))
        .overlay(alignment: .topTrailing) {
            if editable {
                EntryDetailChevron()
                    .padding(.top, 9)
                    .padding(.trailing, 12)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if needsReview {
                EntryDetailReviewBadge().padding(8)
            }
        }
    }

    private var duration: TimeInterval {
        guard let startTime, let endTime else { return 0 }
        return max(0, endTime.timeIntervalSince(startTime))
    }
}

private struct EntryDetailDateText: View {
    let date: Date?
    let timeZoneIdentifier: String

    var body: some View {
        if let date {
            Text(
                "\(date, format: .dateTime.hour().minute()), \(date, format: .dateTime.month(.wide)) \(date, format: .dateTime.day())"
            )
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .environment(
                \.timeZone,
                TimeZone(identifier: timeZoneIdentifier) ?? .current
            )
            .fontWeight(.medium)
        } else {
            Text("Needs review")
                .foregroundStyle(.secondary)
        }
    }
}

private struct EntryDetailDurationRow: View {
    let duration: TimeInterval

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 3) {
                ForEach(0..<3) { _ in
                    Capsule()
                        .fill(.tertiary)
                        .frame(width: 2, height: 8)
                }
            }
            Text(duration, format: .compactDuration)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
    }
}
