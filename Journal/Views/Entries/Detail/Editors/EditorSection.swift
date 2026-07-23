import PhotosUI
import SwiftUI

struct EntryEditorSection<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 18))
    }
}
