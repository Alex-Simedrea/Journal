//
//  ContactsService.swift
//  Journal
//

import Contacts
import Foundation
import SwiftData

nonisolated enum ContactAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case limited
    case denied

    var permitsAccess: Bool {
        self == .authorized || self == .limited
    }
}

nonisolated struct ContactSnapshot: Equatable, Sendable {
    let identifier: String
    let name: String
}

nonisolated struct ContactSyncResult: Equatable, Sendable {
    let addedCount: Int
    let updatedCount: Int
}

nonisolated enum ContactsServiceError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            String(localized: "Contacts access is disabled. You can enable it in Settings.")
        }
    }
}

actor ContactsService {
    static let shared = ContactsService()

    private let store = CNContactStore()

    func authorizationState() -> ContactAuthorizationState {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .authorized
        case .limited:
            .limited
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }

    func requestAccessIfNeeded() async throws -> ContactAuthorizationState {
        let currentState = authorizationState()
        switch currentState {
        case .authorized, .limited:
            return currentState
        case .denied:
            throw ContactsServiceError.accessDenied
        case .notDetermined:
            guard try await store.requestAccess(for: .contacts) else {
                throw ContactsServiceError.accessDenied
            }
            return authorizationState()
        }
    }

    func nameSnapshots() throws -> [ContactSnapshot] {
        guard authorizationState().permitsAccess else {
            return []
        }
        return try allSnapshots()
    }

    func photoData(for identifier: String) throws -> Data? {
        guard authorizationState().permitsAccess else {
            return nil
        }

        do {
            let contact = try store.unifiedContact(
                withIdentifier: identifier,
                keysToFetch: Self.photoKeys
            )
            return contact.thumbnailImageData
        } catch let error as CNError where error.code == .recordDoesNotExist {
            return nil
        }
    }

    private func allSnapshots() throws -> [ContactSnapshot] {
        let request = CNContactFetchRequest(keysToFetch: Self.nameKeys)
        request.sortOrder = .userDefault
        request.unifyResults = true
        var snapshots: [ContactSnapshot] = []

        try store.enumerateContacts(with: request) { contact, _ in
            snapshots.append(
                ContactSnapshot(
                    identifier: contact.identifier,
                    name: Self.displayName(for: contact)
                )
            )
        }
        return snapshots
    }

    private static func displayName(for contact: CNContact) -> String {
        if let formattedName = CNContactFormatter.string(
            from: contact,
            style: .fullName
        ), !formattedName.isEmpty {
            return formattedName
        }
        if !contact.organizationName.isEmpty {
            return contact.organizationName
        }
        if !contact.nickname.isEmpty {
            return contact.nickname
        }
        return String(localized: "Unnamed Contact")
    }

    private static let nameKeys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
    ]

    private static let photoKeys: [CNKeyDescriptor] = [
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
        CNContactImageDataAvailableKey as CNKeyDescriptor,
    ]
}

@MainActor
enum ContactPersonSyncService {
    static func synchronizeAllContacts(
        in modelContext: ModelContext
    ) async throws -> ContactSyncResult {
        let authorizationState = try await ContactsService.shared.requestAccessIfNeeded()
        guard authorizationState.permitsAccess else {
            throw ContactsServiceError.accessDenied
        }

        let snapshots = try await ContactsService.shared.nameSnapshots()
        return try apply(
            snapshots,
            excluding: ContactImportExclusionStore.identifiers,
            to: modelContext
        )
    }

    static func apply(
        _ snapshots: [ContactSnapshot],
        excluding excludedContactIdentifiers: Set<String> = [],
        to modelContext: ModelContext
    ) throws -> ContactSyncResult {
        let people = try modelContext.fetch(FetchDescriptor<Person>())
        let peopleByContactIdentifier = Dictionary(
            grouping: people.compactMap { person -> (String, Person)? in
                guard let contactIdentifier = person.contactIdentifier else {
                    return nil
                }
                return (contactIdentifier, person)
            },
            by: \.0
        )

        var addedCount = 0
        var updatedCount = 0

        for snapshot in snapshots
        where !excludedContactIdentifiers.contains(snapshot.identifier) {
            if let matches = peopleByContactIdentifier[snapshot.identifier] {
                for (_, person) in matches where person.name != snapshot.name {
                    person.name = snapshot.name
                    updatedCount += 1
                }
            } else {
                modelContext.insert(
                    Person(
                        name: snapshot.name,
                        contactIdentifier: snapshot.identifier
                    )
                )
                addedCount += 1
            }
        }

        if addedCount > 0 || updatedCount > 0 {
            try modelContext.save()
        }

        return ContactSyncResult(
            addedCount: addedCount,
            updatedCount: updatedCount
        )
    }
}

@MainActor
enum ContactImportExclusionStore {
    private static let key = "excludedContactImportIdentifiers"

    static var identifiers: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func exclude(_ identifier: String) {
        var updatedIdentifiers = identifiers
        updatedIdentifiers.insert(identifier)
        UserDefaults.standard.set(Array(updatedIdentifiers), forKey: key)
    }
}
