import MapKit
import SwiftData
import SwiftUI

struct WorkoutSummarySection: View {
    let activityName: String
    let activityTypeRawValue: Int
    let movementKind: WorkoutMovementKind
    let startTime: Date?
    let endTime: Date?
    let startTimeZoneIdentifier: String
    let endTimeZoneIdentifier: String
    let distanceMeters: Double?
    let activeEnergyKilocalories: Double?
    let placeName: String
    let originName: String
    let destinationName: String
    let peopleNames: [String]
    let createdAt: Date

    var body: some View {
        Section("Details") {
            LabeledContent("Activity") {
                Label(
                    activityName,
                    systemImage: WorkoutActivityCatalog.presentation(
                        for: activityTypeRawValue
                    ).systemImageName
                )
            }
            Label("Imported from Health", systemImage: "heart.fill")
                .foregroundStyle(.secondary)

            WorkoutPlaceSummaryRows(
                movementKind: movementKind,
                placeName: placeName,
                originName: originName,
                destinationName: destinationName
            )
            if !peopleNames.isEmpty {
                LabeledContent("People", value: peopleNames.formatted())
            }
            EntryDetailDateRow(
                title: "Started",
                date: startTime,
                timeZoneIdentifier: startTimeZoneIdentifier
            )
            EntryDetailDateRow(
                title: "Ended",
                date: endTime,
                timeZoneIdentifier: endTimeZoneIdentifier
            )
            WorkoutDurationRow(startTime: startTime, endTime: endTime)

            if movementKind == .moving {
                WorkoutDistanceRow(distanceMeters: distanceMeters)
            }
            WorkoutEnergyRow(
                activeEnergyKilocalories: activeEnergyKilocalories
            )

            LabeledContent("Created") {
                Text(
                    createdAt,
                    format: .dateTime
                        .day()
                        .month(.abbreviated)
                        .year()
                        .hour()
                        .minute()
                )
            }
        }
    }
}

struct WorkoutPlaceSummaryRows: View {
    let movementKind: WorkoutMovementKind
    let placeName: String
    let originName: String
    let destinationName: String

    var body: some View {
        if movementKind == .moving {
            LabeledContent("Origin", value: originName)
            LabeledContent(
                "Destination",
                value: destinationName
            )
        } else {
            LabeledContent("Place", value: placeName)
        }
    }
}

struct WorkoutDurationRow: View {
    let startTime: Date?
    let endTime: Date?

    var body: some View {
        LabeledContent("Duration") {
            if let startTime, let endTime, endTime > startTime {
                Text(
                    Measurement(
                        value: endTime.timeIntervalSince(startTime) / 60,
                        unit: UnitDuration.minutes
                    ),
                    format: .measurement(width: .abbreviated)
                )
            } else {
                Text("Unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct WorkoutDistanceRow: View {
    let distanceMeters: Double?

    var body: some View {
        LabeledContent("Distance") {
            if let distanceMeters {
                Text(
                    Measurement(
                        value: distanceMeters,
                        unit: UnitLength.meters
                    ),
                    format: .measurement(width: .abbreviated)
                )
            } else {
                Text("Unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct WorkoutEnergyRow: View {
    let activeEnergyKilocalories: Double?

    var body: some View {
        LabeledContent("Active energy") {
            if let activeEnergyKilocalories {
                Text("\(activeEnergyKilocalories, format: .number.precision(.fractionLength(0...1))) kcal")
            } else {
                Text("Unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
