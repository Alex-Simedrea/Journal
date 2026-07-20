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
                .background(PersonMonogramBackground())
                .clipShape(.circle)
                .accessibilityLabel("Monogram for \(name)")
        }
    }
}

private struct PersonMonogramBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 197 / 255, green: 213 / 255, blue: 233 / 255),
                Color(red: 155 / 255, green: 166 / 255, blue: 205 / 255),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
