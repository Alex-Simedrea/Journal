import SwiftData
import SwiftUI

struct TransitOriginReviewSection: View {
    @Bindable var model: TransitReviewModel
    let places: [Place]
    let candidates: [LocationCandidate]
    let reason: String?
    let onChooseLocation: () -> Void

    var body: some View {
        Section("Origin") {
            TransitFieldReviewReason(reason: reason)

            EntryLocationSelectionButton(
                label: "Location",
                title: places.first(where: { $0.id == model.originPlaceID })?.name
                    ?? model.originLocation?.presentationAddress,
                systemImage: places.first(where: { $0.id == model.originPlaceID })?.systemImage
                    ?? .mappin,
                action: onChooseLocation
            )

            TransitPlaceCandidateList(
                candidates: candidates,
                onUse: { model.useCandidate($0, for: .origin) },
                onSave: {
                    model.requestPlace(
                        for: .origin,
                        candidate: $0
                    )
                }
            )
        }
    }
}

struct TransitDestinationReviewSection: View {
    @Bindable var model: TransitReviewModel
    let places: [Place]
    let candidates: [LocationCandidate]
    let reason: String?
    let onChooseLocation: () -> Void

    var body: some View {
        Section("Destination") {
            TransitFieldReviewReason(reason: reason)

            EntryLocationSelectionButton(
                label: "Location",
                title: places.first(where: { $0.id == model.destinationPlaceID })?.name
                    ?? model.destinationLocation?.presentationAddress,
                systemImage: places.first(where: { $0.id == model.destinationPlaceID })?.systemImage
                    ?? .mappin,
                action: onChooseLocation
            )

            TransitPlaceCandidateList(
                candidates: candidates,
                onUse: { model.useCandidate($0, for: .destination) },
                onSave: {
                    model.requestPlace(
                        for: .destination,
                        candidate: $0
                    )
                }
            )
        }
    }
}

struct TransitPlaceCandidateList: View {
    let candidates: [LocationCandidate]
    let onUse: (LocationCandidate) -> Void
    let onSave: (LocationCandidate) -> Void

    var body: some View {
        ForEach(candidates) { candidate in
            TransitPlaceCandidateRow(
                candidate: candidate,
                onUse: { onUse(candidate) },
                onSave: { onSave(candidate) }
            )
        }

    }
}

struct TransitPlaceCandidateRow: View {
    let candidate: LocationCandidate
    let onUse: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.name)
                    .font(.headline)
                if let address = candidate.address {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TransitPlaceCandidateMetrics(candidate: candidate)
            }

            HStack {
                Button("Use Location", action: onUse)
                    .buttonStyle(.borderedProminent)
                Button("Save as Place", action: onSave)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TransitPlaceCandidateMetrics: View {
    let candidate: LocationCandidate

    var body: some View {
        HStack(spacing: 10) {
            if let distance = candidate.distanceKilometers {
                Label {
                    Text("\(distance, format: .number.precision(.fractionLength(1))) km")
                } icon: {
                    Image(systemName: "location")
                }
            }
            if let walking = candidate.walkingDurationMinutes {
                Label {
                    Text("\(walking, format: .number.precision(.fractionLength(0))) min")
                } icon: {
                    Image(systemName: "figure.walk")
                }
            }
            if let automobile = candidate.automobileDurationMinutes {
                Label {
                    Text("\(automobile, format: .number.precision(.fractionLength(0))) min")
                } icon: {
                    Image(systemName: "car")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
