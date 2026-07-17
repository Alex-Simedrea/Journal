//
//  Person.swift
//  Journal
//
//  Created by Alexandru Simedrea on 11/07/2026.
//

import Foundation
import SwiftData

@Model
class Person {
    @Attribute(.unique) var id: UUID
    var name: String
    var aliases: [String]
    var contactIdentifier: String?

    var firstMetAt: Date?
    var firstMetPlace: Place?

    var lastMetAt: Date?
    var lastMetPlace: Place?

    init(
        id: UUID,
        name: String,
        aliases: [String],
        contactIdentifier: String? = nil,
        firstMetAt: Date? = nil,
        firstMetPlace: Place? = nil,
        lastMetAt: Date? = nil,
        lastMetPlace: Place? = nil
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.contactIdentifier = contactIdentifier
        self.firstMetAt = firstMetAt
        self.firstMetPlace = firstMetPlace
        self.lastMetAt = lastMetAt
        self.lastMetPlace = lastMetPlace
    }

    convenience init(
        name: String,
        contactIdentifier: String? = nil
    ) {
        self.init(
            id: UUID(),
            name: name,
            aliases: [],
            contactIdentifier: contactIdentifier
        )
    }
}
