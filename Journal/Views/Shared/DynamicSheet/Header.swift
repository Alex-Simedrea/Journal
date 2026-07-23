import SwiftUI

struct DynamicSheetHeader<Leading: View, Trailing: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let title: LocalizedStringResource
  let isElevated: Bool
  @ViewBuilder let leading: Leading
  @ViewBuilder let trailing: Trailing

  init(
    title: LocalizedStringResource,
    isElevated: Bool,
    @ViewBuilder leading: () -> Leading,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.isElevated = isElevated
    self.leading = leading()
    self.trailing = trailing()
  }

  var body: some View {
    ZStack {
      Text(title)
        .font(.title3.weight(.semibold))
        .lineLimit(1)

      HStack {
        leading
        Spacer()
        trailing
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 16)
    .padding(.bottom, 14)
    .background {
      GeometryReader { geometry in
        VariableBlurView(
          maxBlurRadius: 6,
          direction: .blurredTopClearBottom,
        )
        .frame(
          width: geometry.size.width,
          height: geometry.size.height
        )
        .opacity(isElevated ? 1 : 0)
        .allowsHitTesting(false)
      }
    }
    .animation(
      reduceMotion ? nil : .easeOut(duration: 0.16),
      value: isElevated
    )
  }
}
