import MapKit
import SwiftData
import SwiftUI

struct WorkoutReviewSection: View {
    let reviews: [WorkoutFieldReview]

    var body: some View {
        if !reviews.isEmpty {
            Section("Needs Review") {
                ForEach(reviews) { review in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(review.field.title)
                                .fontWeight(.semibold)
                            Text(review.reason)
                                .font(.caption)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                    }
                    .foregroundStyle(.orange)
                }
            }
        }
    }
}
