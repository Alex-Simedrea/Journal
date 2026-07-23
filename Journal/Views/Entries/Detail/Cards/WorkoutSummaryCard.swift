import MapKit
import Photos
import SwiftUI

struct EntryDetailWorkoutCard: View {
    let details: WorkoutDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineFixedSymbol(
                systemName: WorkoutActivityCatalog.presentation(
                    for: details.activityTypeRawValue
                ).systemImageName,
                size: 23,
                weight: .semibold
            )
            Text(details.activityName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(metrics)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.black)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(
            maxWidth: .infinity,
            minHeight: 88,
            maxHeight: .infinity,
            alignment: .leading
        )
        .background(Color(hex: 0xB6FF00), in: .rect(cornerRadius: 22))
    }

    private var metrics: String {
        var values: [String] = []
        if let energy = details.activeEnergyKilocalories {
            values.append(
                energy.formatted(
                    .number.precision(.fractionLength(0))
                ) + "KCAL"
            )
        }
        if let distance = details.distanceMeters {
            values.append(
                Measurement(value: distance, unit: UnitLength.meters)
                    .formatted(.measurement(width: .abbreviated))
            )
        }
        return values.isEmpty
            ? String(localized: "Health workout")
            : values.joined(separator: " • ")
    }
}
