//
//  ContactAvatarModel.swift
//  Journal
//

import Foundation
import Observation

@MainActor
@Observable
final class ContactAvatarModel {
    private(set) var imageData: Data?

    func load(contactIdentifier: String?) async {
        guard let contactIdentifier else {
            imageData = nil
            return
        }

        imageData = try? await ContactsService.shared.photoData(
            for: contactIdentifier
        )
    }
}
