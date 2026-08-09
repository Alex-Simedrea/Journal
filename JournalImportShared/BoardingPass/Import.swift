import CryptoKit
import Foundation
import PassKit
import ZIPFoundation

enum JournalImportConfiguration {
    static let appGroupIdentifier = "group.ro.attractivestar.Journal"
    static let boardingPassTypeIdentifier = "com.apple.pkpass"
}

struct JourneyLocalDateTime: Codable, Hashable {
    var year: Int
    var month: Int
    var day: Int
    var hour: Int
    var minute: Int
    var timeZoneOffsetSeconds: Int?

    func date(in timeZone: TimeZone? = nil) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
            ?? timeZoneOffsetSeconds.flatMap { TimeZone(secondsFromGMT: $0) }
            ?? .current
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )
    }
}

struct PendingBoardingPassImport: Codable, Hashable, Identifiable {
    var id: UUID
    var importedAt: Date
    var sourceFingerprint: String
    var organizationName: String?
    var passDescription: String?
    var transitTypeName: String?
    var originName: String?
    var originAirportCode: String?
    var destinationName: String?
    var destinationAirportCode: String?
    var startTime: Date?
    var endTime: Date?
    var startLocalDateTime: JourneyLocalDateTime?
    var endLocalDateTime: JourneyLocalDateTime?
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
        originAirportCode: String? = nil,
        destinationName: String? = nil,
        destinationAirportCode: String? = nil,
        startTime: Date? = nil,
        endTime: Date? = nil,
        startLocalDateTime: JourneyLocalDateTime? = nil,
        endLocalDateTime: JourneyLocalDateTime? = nil,
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
        self.originAirportCode = originAirportCode
        self.destinationName = destinationName
        self.destinationAirportCode = destinationAirportCode
        self.startTime = startTime
        self.endTime = endTime
        self.startLocalDateTime = startLocalDateTime
        self.endLocalDateTime = endLocalDateTime
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
    case invalidFlightSummary

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
            "No supported boarding pass or flight summary was included in the shared item."
        case .invalidFlightSummary:
            "The shared text is not a Flighty flight summary."
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
            matching: ["departure", "depart", "origin", "from"]
        ) ?? boardingPass.primaryFields.first
        let destinationField = endpointField(
            in: boardingPass.primaryFields,
            matching: ["arrival", "arrive", "destination", "to"]
        ) ?? boardingPass.primaryFields.dropFirst().first
        let originDetailsField = endpointField(
            in: boardingPass.backFields,
            matching: ["departure", "depart", "origin", "from"]
        )
        let destinationDetailsField = endpointField(
            in: boardingPass.backFields,
            matching: ["arrival", "arrive", "destination", "to"]
        )
        let relevantInterval = document.relevantDates?.first(where: {
            $0.startDate != nil && $0.endDate != nil
        })
        let relevantStartValue = relevantInterval?.startDate
            ?? document.relevantDate
        let startLocalDateTime = localDateTime(
            from: originDetailsField,
            fallbackISO8601Value: relevantStartValue
        )
        let endLocalDateTime = localDateTime(
            from: destinationDetailsField,
            fallbackISO8601Value: relevantInterval?.endDate
        )
        let startTime = parseISO8601(relevantStartValue)
            ?? startLocalDateTime?.date()
        let endTime = parseISO8601(relevantInterval?.endDate)
            ?? provisionalEndTime(
                endLocalDateTime,
                startOffsetSeconds: startLocalDateTime?.timeZoneOffsetSeconds
            )
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
            originName: endpointName(
                originField,
                detailsField: originDetailsField
            ),
            originAirportCode: airportCode(from: originField),
            destinationName: endpointName(
                destinationField,
                detailsField: destinationDetailsField
            ),
            destinationAirportCode: airportCode(from: destinationField),
            startTime: startTime,
            endTime: endTime,
            startLocalDateTime: startLocalDateTime,
            endLocalDateTime: endLocalDateTime,
            serviceIdentifier: serviceIdentifier(in: boardingPass),
            warnings: warnings
        )
    }

    static func parse(flightSummary text: String) throws -> PendingBoardingPassImport {
        let normalized = normalizedFlightSummaryText(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let header = lines.first,
              let headerMatch = firstMatch(
                in: header,
                pattern: #"^(.+?)\s+((?:[A-Z0-9]{2,3}\s*)?\d{1,4}[A-Z]?)\s+on\s+(\d{1,2}\s+[\p{L}.]+\s+\d{4})$"#
              ),
              let route = lines.lazy.compactMap({ line in
                firstMatch(in: line, pattern: #"^(.+?)\s+to\s+(.+)$"#)
              }).first,
              let departureLine = lines.first(where: { $0.hasPrefix("↗") }),
              let arrivalLine = lines.first(where: { $0.hasPrefix("↘") }),
              let travelDate = flightyDate(headerMatch[3]),
              let departureClock = flightyClock(
                in: departureLine,
                on: travelDate
              ),
              let arrivalClock = flightyClock(
                in: arrivalLine,
                on: travelDate
              ),
              let startLocal = journeyDateTime(
                date: travelDate,
                clock: departureClock
              ),
              var endLocal = journeyDateTime(
                date: travelDate,
                clock: arrivalClock
              ),
              let startTime = startLocal.date(),
              var endTime = endLocal.date() else {
            throw BoardingPassImportError.invalidFlightSummary
        }

        if endTime <= startTime {
            guard let nextDay = Calendar(identifier: .gregorian).date(
                byAdding: .day,
                value: 1,
                to: endTime
            ) else {
                throw BoardingPassImportError.invalidFlightSummary
            }
            endTime = nextDay
            var arrivalCalendar = Calendar(identifier: .gregorian)
            arrivalCalendar.timeZone = TimeZone(
                secondsFromGMT: arrivalClock.offset
            ) ?? .current
            let nextDayComponents = arrivalCalendar.dateComponents(
                [.year, .month, .day],
                from: nextDay
            )
            endLocal.year = nextDayComponents.year ?? endLocal.year
            endLocal.month = nextDayComponents.month ?? endLocal.month
            endLocal.day = nextDayComponents.day ?? endLocal.day
        }

        let organizationName = nonempty(headerMatch[1])
        let serviceIdentifier = nonempty(headerMatch[2])

        return PendingBoardingPassImport(
            sourceFingerprint: sha256(Data(normalized.utf8)),
            organizationName: organizationName,
            passDescription: header,
            transitTypeName: "Flight",
            originName: nonempty(route[1]),
            originAirportCode: flightyAirportCode(in: departureLine),
            destinationName: nonempty(route[2]),
            destinationAirportCode: flightyAirportCode(in: arrivalLine),
            startTime: startTime,
            endTime: endTime,
            startLocalDateTime: startLocal,
            endLocalDateTime: endLocal,
            serviceIdentifier: serviceIdentifier,
            warnings: []
        )
    }

    private static func normalizedFlightSummaryText(_ text: String) -> String {
        text.unicodeScalars.reduce(into: "") { result, scalar in
            switch scalar.value {
            case 0, 0xFEFF, 0x200E, 0x200F, 0x2066...0x2069,
                 0xFE0E, 0xFE0F:
                break
            case 0x0085, 0x2028, 0x2029:
                result.append("\n")
            default:
                if scalar.properties.generalCategory == .spaceSeparator {
                    result.append(" ")
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
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

    private static func endpointName(
        _ field: WalletPassField?,
        detailsField: WalletPassField?
    ) -> String? {
        if let detailedName = locationName(from: detailsField) {
            return detailedName
        }
        guard let field else { return nil }
        let value = nonempty(field.value.displayString)
        let label = nonempty(field.label)

        if let value, looksLikeAirportCode(value), let label,
           !looksLikeGenericEndpointLabel(label) {
            return label.localizedCapitalized
        }
        if let value, !looksLikeTime(value), !looksLikeDate(value) {
            return value
        }
        return label ?? value
    }

    private static func airportCode(from field: WalletPassField?) -> String? {
        let candidates = [
            field?.value.displayString,
            field?.label,
        ]
        for candidate in candidates {
            guard let candidate = nonempty(candidate) else { continue }
            let code = candidate.uppercased()
            if looksLikeAirportCode(code) {
                return code
            }
        }
        return nil
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

    private static func localDateTime(
        from field: WalletPassField?,
        fallbackISO8601Value: String?
    ) -> JourneyLocalDateTime? {
        if let value = nonempty(field?.value.displayString),
           let parsed = localDateTime(fromBackFieldValue: value) {
            return JourneyLocalDateTime(
                year: parsed.year,
                month: parsed.month,
                day: parsed.day,
                hour: parsed.hour,
                minute: parsed.minute,
                timeZoneOffsetSeconds: iso8601OffsetSeconds(
                    fallbackISO8601Value
                )
            )
        }
        guard let date = parseISO8601(fallbackISO8601Value) else { return nil }
        let offset = iso8601OffsetSeconds(fallbackISO8601Value)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = offset.flatMap { TimeZone(secondsFromGMT: $0) }
            ?? .current
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let hour = components.hour,
              let minute = components.minute else { return nil }
        return JourneyLocalDateTime(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            timeZoneOffsetSeconds: offset
        )
    }

    private static func localDateTime(
        fromBackFieldValue value: String
    ) -> JourneyLocalDateTime? {
        guard let dateLine = value
            .split(separator: "\n")
            .map(String.init)
            .last else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "h:mma, MMM dd, yyyy"
        guard let date = formatter.date(from: dateLine) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let hour = components.hour,
              let minute = components.minute else { return nil }
        return JourneyLocalDateTime(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            timeZoneOffsetSeconds: nil
        )
    }

    private static func provisionalEndTime(
        _ localDateTime: JourneyLocalDateTime?,
        startOffsetSeconds: Int?
    ) -> Date? {
        guard var localDateTime else { return nil }
        localDateTime.timeZoneOffsetSeconds = startOffsetSeconds
        return localDateTime.date()
    }

    private static func locationName(from field: WalletPassField?) -> String? {
        guard let value = nonempty(field?.value.displayString),
              let firstLine = value.split(separator: "\n").first else {
            return nil
        }
        let pieces = firstLine.split(separator: ":", maxSplits: 1)
        guard pieces.count == 2,
              let city = pieces[1].split(separator: ",").first else {
            return nil
        }
        return nonempty(String(city))
    }

    private static func iso8601OffsetSeconds(_ value: String?) -> Int? {
        guard let value else { return nil }
        if value.hasSuffix("Z") { return 0 }
        guard let match = firstMatch(
            in: value,
            pattern: #"([+-])(\d{2}):(\d{2})$"#
        ), let hours = Int(match[2]), let minutes = Int(match[3]) else {
            return nil
        }
        let sign = match[1] == "-" ? -1 : 1
        return sign * ((hours * 60 + minutes) * 60)
    }

    private static func flightyDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.date(from: value)
    }

    private static func flightyClock(
        in line: String,
        on date: Date
    ) -> (hour: Int, minute: Int, offset: Int)? {
        guard let match = firstMatch(
            in: line,
            pattern: #"(\d{1,2}):(\d{2})\s+((?:GMT|UTC)[+-]\d{1,2}(?::?\d{2})?|[A-Z]{2,5})\b"#
        ), let hour = Int(match[1]),
           let minute = Int(match[2]),
           let offset = flightyTimeZoneOffset(
            for: match[3],
            on: date
           ) else { return nil }
        return (hour, minute, offset)
    }

    private static func flightyTimeZoneOffset(
        for token: String,
        on date: Date
    ) -> Int? {
        if let match = firstMatch(
            in: token,
            pattern: #"^(?:GMT|UTC)([+-])(\d{1,2})(?::?(\d{2}))?$"#
        ), let hours = Int(match[2]) {
            let minutes = match.count > 3 ? Int(match[3]) ?? 0 : 0
            let sign = match[1] == "-" ? -1 : 1
            return sign * ((hours * 60 + minutes) * 60)
        }
        return TimeZone(abbreviation: token.uppercased())?
            .secondsFromGMT(for: date)
    }

    private static func flightyAirportCode(in line: String) -> String? {
        guard let match = firstMatch(
            in: line,
            pattern: #"\s([A-Z]{3})\s*(?:\([^)]*\))?\s*$"#
        ) else { return nil }
        return nonempty(match[1])?.uppercased()
    }

    private static func journeyDateTime(
        date: Date,
        clock: (hour: Int, minute: Int, offset: Int)
    ) -> JourneyLocalDateTime? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else { return nil }
        return JourneyLocalDateTime(
            year: year,
            month: month,
            day: day,
            hour: clock.hour,
            minute: clock.minute,
            timeZoneOffsetSeconds: clock.offset
        )
    }

    private static func firstMatch(
        in value: String,
        pattern: String
    ) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
              ) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound,
                  let swiftRange = Range(range, in: value) else { return "" }
            return String(value[swiftRange])
        }
    }

    private static func looksLikeAirportCode(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z]{3}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func looksLikeGenericEndpointLabel(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return ["from", "to", "origin", "destination", "depart", "departure",
                "arrive", "arrival"].contains(normalized)
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

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
