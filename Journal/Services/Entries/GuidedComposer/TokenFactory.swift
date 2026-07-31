import Foundation

enum ComposerTokenFactory {
    static func connector(_ connector: ComposerConnector) -> ComposerToken {
        ComposerToken(
            displayText: connector.rawValue,
            value: .connector(connector)
        )
    }

    static func location(
        _ location: ComposerLocationCandidate,
        role: ComposerLocationRole
    ) -> ComposerToken {
        ComposerToken(
            displayText: location.displayName,
            value: .location(location, role)
        )
    }

    static func time(
        _ value: ComposerTimeValue,
        role: ComposerTimeRole,
        displayText: String? = nil
    ) -> ComposerToken {
        let zone = TimeZone(
            identifier: value.timeZoneIdentifier
        ) ?? .current
        return ComposerToken(
            displayText: displayText
                ?? GuidedComposerTimeParser.displayTime(
                    value.date,
                    timeZone: zone
                ),
            value: .time(value, role)
        )
    }

    static func explicitTime(
        date: Date,
        timeZone: TimeZone,
        role: ComposerTimeRole,
        displayText: String,
        allowsOvernightRollover: Bool
    ) -> ComposerToken {
        time(
            ComposerTimeValue(
                date: date,
                timeZoneIdentifier: timeZone.identifier,
                source: .explicit,
                allowsOvernightRollover: allowsOvernightRollover
            ),
            role: role,
            displayText: displayText
        )
    }
}

enum ComposerSlotPresentation {
    static func subtitle(for slot: ComposerSlot) -> String? {
        switch slot {
        case .location(.visit): String(localized: "Visit place")
        case .location(.origin): String(localized: "Origin")
        case .location(.destination): String(localized: "Destination")
        case .time(.start): String(localized: "Start time")
        case .time(.end): String(localized: "End time")
        case .duration: String(localized: "Duration")
        case .person: String(localized: "People")
        case .leading, .connector: nil
        }
    }

    static func systemImage(for slot: ComposerSlot) -> String {
        switch slot {
        case .location(.visit), .location(.destination): "mappin"
        case .location(.origin): "location"
        case .time: "clock"
        case .duration: "timer"
        case .person: "person.2"
        case .leading, .connector: "arrow.right"
        }
    }
}
