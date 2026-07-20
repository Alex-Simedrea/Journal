//
//  TransitPresentationIcon.swift
//  Journal
//

import SwiftUI

struct TransitPresentationIcon: View {
    let presentation: TransitPresentation
    let size: CGFloat
    let weight: Font.Weight

    init(
        presentation: TransitPresentation,
        size: CGFloat,
        weight: Font.Weight = .regular
    ) {
        self.presentation = presentation
        self.size = size
        self.weight = weight
    }

    var body: some View {
        ZStack {
            if let brandImage = presentation.brandImage {
                Image(brandImage.rawValue)
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)
            } else {
                TimelineFixedSymbol(
                    systemName: presentation.systemImageName,
                    size: size,
                    weight: weight
                )
            }
        }
        .frame(width: size, height: size)
    }
}
