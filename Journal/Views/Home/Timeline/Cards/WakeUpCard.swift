import MapKit
import Photos
import SwiftUI

struct TimelineWakeUpRow: View {
    let occurrence: TimelineOccurrence

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "alarm")
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 13, height: 13)
                .frame(width: 26, height: 26)
                .background(
                    .teal.gradient,
                    in: .circle
                )

            VStack(alignment: .leading, spacing: 0) {
                Text("Wake up")
                    .font(.headline)
                TimelineWakeUpDurationLabel(
                    durationSeconds: occurrence.wakeUpSleepDurationSeconds
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 49, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct TimelineWakeUpDurationLabel: View {
    let durationSeconds: TimeInterval?

    var body: some View {
        if let durationSeconds {
            Text(
                Duration.seconds(durationSeconds),
                format: .units(
                    allowed: [.hours, .minutes],
                    width: .narrow,
                    maximumUnitCount: 2,
                    zeroValueUnits: .hide
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}
