import SwiftData
import SwiftUI

struct TransitEntryKindReviewSection: View {
    let reason: String?
    let onSwitch: () -> Void

    var body: some View {
        Section {
            EntryReviewReason(reason: reason)
            LabeledContent("Selected type", value: "Transit")
            Button("Switch to Place Visit", action: onSwitch)
        } header: {
            Text("Entry type")
        } footer: {
            Text("Saving confirms this as transit.")
        }
    }
}

struct TransitReviewExplanation: View {
    var body: some View {
        Section {
            Label(
                "Only the uncertain parts of this entry are shown.",
                systemImage: "exclamationmark.circle.fill"
            )
            .foregroundStyle(.orange)
        }
    }
}

struct TransitTypeReviewSection: View {
    @Bindable var model: TransitReviewModel
    let transitTypes: [TransitType]
    let reason: String?

    var body: some View {
        Section("Transit type") {
            TransitFieldReviewReason(reason: reason)
            Picker("Type", selection: $model.transitType) {
                ForEach(transitTypes) { type in
                    Text(type.canonicalName).tag(type.canonicalName)
                }
                if !transitTypes.contains(where: {
                    $0.canonicalName == model.transitType
                }), !model.transitType.isEmpty {
                    Text(model.transitType).tag(model.transitType)
                }
            }
        }
    }
}
