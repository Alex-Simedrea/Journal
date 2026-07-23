import CryptoKit
import Foundation
import PassKit
import ZIPFoundation

enum JournalImportConfiguration {
    static let appGroupIdentifier = "group.ro.attractivestar.Journal"
    static let boardingPassTypeIdentifier = "com.apple.pkpass"
}
struct PendingBoardingPassImport: Codable, Hashable, Identifiable {
    var id: UUID
    var importedAt: Date
    var sourceFingerprint: String
    var organizationName: String?
    var passDescription: String?
    var transitTypeName: String?
    var originName: String?
    var destinationName: String?
    var startTime: Date?
    var endTime: Date?
    var serviceIdentifier: String?
    var warnings: [String]

    init(
        id: UUID = UUID(),
        importedAt: Date = .now,
        sourceFingerprint: String,
        organizationName: String? = nil,
        passDescription: String? = nil,
        transitTypeName: String? = nil,
        originName: String? = nil,
        destinationName: String? = nil,
        startTime: Date? = nil,
        endTime: Date? = nil,
        serviceIdentifier: String? = nil,
        warnings: [String] = []
    ) {
        self.id = id
        self.importedAt = importedAt
        self.sourceFingerprint = sourceFingerprint
        self.organizationName = organizationName
        self.passDescription = passDescription
        self.transitTypeName = transitTypeName
        self.originName = originName
        self.destinationName = destinationName
        self.startTime = startTime
        self.endTime = endTime
        self.serviceIdentifier = serviceIdentifier
        self.warnings = warnings
    }
}

enum BoardingPassImportError: LocalizedError {
    case invalidPass
    case missingPassJSON
    case passJSONTooLarge
    case unsupportedPass
    case unavailableSharedContainer
    case noBoardingPassAttachment

    var errorDescription: String? {
        switch self {
        case .invalidPass:
            "The shared file is not a valid Wallet pass."
        case .missingPassJSON:
            "The Wallet pass does not contain its expected pass data."
        case .passJSONTooLarge:
            "The Wallet pass data is unexpectedly large."
        case .unsupportedPass:
            "This Wallet pass does not contain boarding-pass details."
        case .unavailableSharedContainer:
            "Journal’s shared import container is unavailable."
        case .noBoardingPassAttachment:
            "No boarding pass was included in the shared item."
        }
    }
}

enum BoardingPassImporter {
    private static let maximumPassJSONSize = 1_000_000

    static func parse(data: Data) throws -> PendingBoardingPassImport {
        do {
            _ = try PKPass(data: data)
        } catch {
            throw BoardingPassImportError.invalidPass
        }

        let archive: Archive
        do {
            archive = try Archive(
                data: data,
                accessMode: .read,
                pathEncoding: nil
            )
        } catch {
            throw BoardingPassImportError.invalidPass
        }
        guard let entry = archive["pass.json"] else {
            throw BoardingPassImportError.missingPassJSON
        }
        guard entry.uncompressedSize <= maximumPassJSONSize else {
            throw BoardingPassImportError.passJSONTooLarge
        }

        var passJSON = Data()
        _ = try archive.extract(entry) { chunk in
            passJSON.append(chunk)
        }

        return try parse(
            passJSONData: passJSON,
            fallbackFingerprintData: data
        )
    }

    static func parse(
        passJSONData: Data,
        fallbackFingerprintData: Data = Data()
    ) throws -> PendingBoardingPassImport {
        let document = try JSONDecoder().decode(
            WalletPassDocument.self,
            from: passJSONData
        )
        guard let boardingPass = document.boardingPass else {
            throw BoardingPassImportError.unsupportedPass
        }

        let originField = endpointField(
            in: boardingPass.primaryFields,
            matching: ["departure", "origin", "from"]
        ) ?? boardingPass.primaryFields.first
        let destinationField = endpointField(
            in: boardingPass.primaryFields,
            matching: ["arrival", "destination", "to"]
        ) ?? boardingPass.primaryFields.dropFirst().first
        let relevantInterval = document.relevantDates?.first(where: {
            $0.startDate != nil && $0.endDate != nil
        })
        let startTime = parseISO8601(relevantInterval?.startDate)
            ?? parseISO8601(document.relevantDate)
        let endTime = parseISO8601(relevantInterval?.endDate)
            ?? parseISO8601(document.expirationDate)
        let fingerprintSource: Data
        if let passTypeIdentifier = document.passTypeIdentifier,
           let serialNumber = document.serialNumber {
            fingerprintSource = Data(
                "\(passTypeIdentifier)|\(serialNumber)".utf8
            )
        } else if !fallbackFingerprintData.isEmpty {
            fingerprintSource = fallbackFingerprintData
        } else {
            fingerprintSource = passJSONData
        }

        var warnings: [String] = []
        if boardingPass.transitType == nil {
            warnings.append("The pass does not identify its transit type.")
        }
        if originField == nil {
            warnings.append("The pass does not identify an origin.")
        }
        if destinationField == nil {
            warnings.append("The pass does not identify a destination.")
        }
        if startTime == nil || endTime == nil {
            warnings.append("The pass does not provide a complete travel interval.")
        }

        return PendingBoardingPassImport(
            sourceFingerprint: SHA256.hash(data: fingerprintSource)
                .map { String(format: "%02x", $0) }
                .joined(),
            organizationName: nonempty(document.organizationName),
            passDescription: nonempty(document.description),
            transitTypeName: canonicalTransitType(boardingPass.transitType),
            originName: endpointName(originField),
            destinationName: endpointName(destinationField),
            startTime: startTime,
            endTime: endTime,
            serviceIdentifier: serviceIdentifier(in: boardingPass),
            warnings: warnings
        )
    }

    private static func endpointField(
        in fields: [WalletPassField],
        matching terms: [String]
    ) -> WalletPassField? {
        fields.first { field in
            let key = field.key.lowercased()
            return terms.contains { key.contains($0) }
        }
    }

    private static func endpointName(_ field: WalletPassField?) -> String? {
        guard let field else { return nil }
        let value = nonempty(field.value.displayString)
        let label = nonempty(field.label)

        if let value, !looksLikeTime(value), !looksLikeDate(value) {
            return value
        }
        return label ?? value
    }

    private static func serviceIdentifier(
        in boardingPass: WalletBoardingPass
    ) -> String? {
        let fields = boardingPass.auxiliaryFields
            + boardingPass.secondaryFields
            + boardingPass.headerFields
        let preferredTerms = [
            "train", "trains", "flight", "flightnumber", "service",
            "route", "vehicle",
        ]
        let preferred = fields.first { field in
            let key = field.key.lowercased()
            return preferredTerms.contains { key.contains($0) }
        }
        return nonempty(preferred?.value.displayString)
    }

    private static func canonicalTransitType(_ value: String?) -> String? {
        switch value {
        case "PKTransitTypeAir": "Flight"
        case "PKTransitTypeTrain": "Train"
        case "PKTransitTypeBus": "Bus"
        case "PKTransitTypeBoat": "Ferry"
        case "PKTransitTypeGeneric": nil
        default: nil
        }
    }

    private static func parseISO8601(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func looksLikeTime(_ value: String) -> Bool {
        value.range(
            of: #"^\s*\d{1,2}[:.]\d{2}(?:\s*[APap][Mm])?\s*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func looksLikeDate(_ value: String) -> Bool {
        value.range(
            of: #"^\s*\d{1,4}[-./]\d{1,2}[-./]\d{1,4}\s*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
