import SwiftUI

#if DEBUG
@MainActor
private struct EntryDetailPeopleCardPreview: View {
    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
            ) {
                ForEach(EntryDetailPeoplePreviewData.variants) { variant in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(variant.count) people")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        EntryDetailPeopleCard(
                            people: variant.people,
                            needsReview: variant.count == 4,
                            onEdit: {}
                        )
                    }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct EntryDetailPeoplePreviewVariant: Identifiable {
    let count: Int
    let people: [Person]

    var id: Int { count }
}

@MainActor
private enum EntryDetailPeoplePreviewData {
    static let variants = (0...12).map { count in
        EntryDetailPeoplePreviewVariant(
            count: count,
            people: (0..<count).map { index in
                Person(name: "Person \(index + 1)")
            }
        )
    }
}

#Preview("People card · 0–12") {
    EntryDetailPeopleCardPreview()
}
#endif
