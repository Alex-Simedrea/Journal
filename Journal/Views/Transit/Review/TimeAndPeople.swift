import SwiftData
import SwiftUI

struct TransitTimeReviewSection: View {
    @Bindable var model: TransitReviewModel
    let reason: String?

    var body: some View {
        Section("Time") {
            TransitFieldReviewReason(reason: reason)
            HStack {
                Button("Just now") { model.useJustNow() }
                    .buttonStyle(.bordered)
                Button("Earlier today") { model.useEarlierToday() }
                    .buttonStyle(.bordered)
            }

            DatePicker("Started", selection: $model.startTime)
            DatePicker("Ended", selection: $model.endTime, in: model.startTime...)
        }
    }
}

struct TransitPeopleReviewSection: View {
    @Bindable var model: TransitReviewModel
    let people: [Person]
    let reason: String?

    var body: some View {
        Section("People") {
            TransitFieldReviewReason(reason: reason)
            ForEach($model.personResolutions) { $resolution in
                Picker("Person", selection: $resolution.personID) {
                    Text("Choose a person").tag(nil as UUID?)
                    ForEach(people) { person in
                        Text(person.name).tag(person.id as UUID?)
                    }
                }
            }
        }
    }
}

struct TransitFieldReviewReason: View {
    let reason: String?

    var body: some View {
        if let reason, !reason.isEmpty {
            Label(reason, systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(.orange)
        }
    }
}
