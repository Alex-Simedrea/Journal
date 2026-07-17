//
//  PersonAvatar.swift
//  Journal
//

import SwiftUI
import UIKit

struct PersonAvatar: View {
    let name: String
    let contactIdentifier: String?
    let size: CGFloat

    @State private var model = ContactAvatarModel()

    var body: some View {
        PersonAvatarImage(
            name: name,
            imageData: model.imageData,
            size: size
        )
        .task(id: contactIdentifier) {
            await model.load(contactIdentifier: contactIdentifier)
        }
    }
}

struct PersonAvatarImage: View {
    let name: String
    let imageData: Data?
    let size: CGFloat

    var body: some View {
        if let imageData,
           let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(.circle)
                .accessibilityLabel("Contact photo for \(name)")
        } else {
            Text(PersonMonogram.initials(for: name))
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.blue.gradient, in: .circle)
                .accessibilityLabel("Monogram for \(name)")
        }
    }
}
