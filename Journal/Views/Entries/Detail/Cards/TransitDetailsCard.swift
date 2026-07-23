import MapKit
import Photos
import SwiftUI

struct EntryDetailTransitCard: View {
    let details: TransitDetails
    let needsReview: Bool
    let onEdit: () -> Void

    var body: some View {
        let presentation = TransitPresentationCatalog.presentation(
            for: details.type
        )
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 2) {
                if presentation.brandImage != nil {
                    TransitPresentationIcon(
                        presentation: presentation,
                        size: 42,
                        weight: .semibold
                    )
                } else {
                    TransitPresentationIcon(
                        presentation: presentation,
                        size: 23,
                        weight: .semibold
                    )
                    Text(details.type)
                        .font(.headline)
                        .lineLimit(1)
                }
                if let operatorName = details.sourceOrganizationName,
                    !operatorName.isEmpty
                {
                    Text(operatorName)
                        .font(.caption)
                        .foregroundStyle(
                            presentation.foregroundColor.opacity(0.75)
                        )
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(metadataText)
                    .font(.subheadline)
                    .foregroundStyle(presentation.foregroundColor.opacity(0.82))
                    .lineLimit(1)
            }
            .padding(.leading, 13)
            .padding(.trailing, 32)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: details.type))
        .accessibilityValue(Text(verbatim: metadataText))
        .foregroundStyle(presentation.foregroundColor)
        .frame(maxHeight: .infinity)
        .background(presentation.color, in: .rect(cornerRadius: 22))
        .overlay(alignment: .topTrailing) {
            EntryDetailChevron()
                .foregroundStyle(presentation.foregroundColor)
                .padding(.top, 11)
                .padding(.trailing, 12)
        }
        .overlay(alignment: .bottomTrailing) {
            if needsReview {
                EntryDetailReviewBadge().padding(8)
            }
        }
    }

    private var metadataText: String {
        var components: [String] = []
        if let identifier = details.sourceServiceIdentifier,
            !identifier.isEmpty
        {
            components.append(identifier)
        }
        if let distance = details.distanceMeters {
            components.append(
                Measurement(value: distance, unit: UnitLength.meters)
                    .formatted(.measurement(width: .abbreviated))
            )
        }
        return components.isEmpty
            ? String(localized: "Distance unavailable")
            : components.joined(separator: " • ")
    }
}
