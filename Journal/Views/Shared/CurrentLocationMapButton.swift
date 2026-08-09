import SwiftUI

struct CurrentLocationMapButton: View {
    let isResolving: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "location.fill")
                    .opacity(isResolving ? 0 : 1)
                if isResolving {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .font(.title3.weight(.medium))
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(isResolving)
        .accessibilityLabel("Current Location")
    }
}
