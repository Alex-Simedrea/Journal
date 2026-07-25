import SwiftUI

struct ZonedDateRow: View {
    let title: LocalizedStringResource
    let date: Date?
    let timeZoneIdentifier: String

    var body: some View {
        LabeledContent(title) {
            if let date {
                HStack(spacing: 5) {
                    Text(
                        date,
                        format: .dateTime
                            .day()
                            .month(.abbreviated)
                            .year()
                            .hour()
                            .minute()
                    )
                    if timeZoneIdentifier != TimeZone.current.identifier {
                        Text(
                            timeZone.abbreviation(for: date)
                                ?? timeZone.identifier
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                .environment(\.timeZone, timeZone)
            } else {
                Text("Unresolved")
            }
        }
    }

    private var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }
}
