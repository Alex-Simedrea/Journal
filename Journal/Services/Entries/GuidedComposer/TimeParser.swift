import Foundation

enum GuidedComposerTimeParser {
    private static let durationExpression = try? NSRegularExpression(
        pattern:
            #"(?:(\d+(?:\.\d+)?)\s*h)?\s*(?:(\d+(?:\.\d+)?)\s*m)?"#,
        options: [.caseInsensitive]
    )
    private static let clockExpression = try? NSRegularExpression(
        pattern: #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$"#,
        options: [.caseInsensitive]
    )
    private static let relativeExpression = try? NSRegularExpression(
        pattern:
            #"^(\d+(?:\.\d+)?)\s*(minutes?|mins?|m|hours?|hrs?|h)\s+ago$"#,
        options: [.caseInsensitive]
    )
    private static var explicitDateFormatters:
        [ExplicitDateFormatterKey: [DateFormatter]] = [:]

    static func parseTime(
        _ rawValue: String,
        role: ComposerTimeRole,
        selectedDay: TimelineDayKey,
        timeZone: TimeZone,
        now: Date = .now
    ) -> Date? {
        let value = GuidedComposerNormalization.text(rawValue)
        guard !value.isEmpty else { return nil }

        let isToday = selectedDay == .today(now: now, timeZone: timeZone)
        if value == "now" || value == "just now" {
            return isToday ? now : nil
        }
        if value == "an hour ago" || value == "one hour ago" {
            return isToday ? now.addingTimeInterval(-60 * 60) : nil
        }
        if value == "half an hour ago" || value == "half hour ago" {
            return isToday ? now.addingTimeInterval(-30 * 60) : nil
        }
        if let relative = relativeOffset(value), isToday {
            return now.addingTimeInterval(-relative)
        }

        var day = selectedDay
        var clockText = value
        for (prefix, offset) in [
            ("yesterday ", -1),
            ("today ", 0),
            ("tomorrow ", 1),
        ] {
            if clockText.hasPrefix(prefix) {
                day = selectedDay.addingDays(offset)
                clockText.removeFirst(prefix.count)
                if clockText.hasPrefix("at ") {
                    clockText.removeFirst(3)
                }
                break
            }
        }

        guard let components = clockComponents(clockText) else {
            return parseExplicitDate(
                value,
                timeZone: timeZone
            )
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var dateComponents = DateComponents(
            timeZone: timeZone,
            year: day.year,
            month: day.month,
            day: day.day,
            hour: components.hour,
            minute: components.minute
        )
        if role == .end {
            dateComponents.second = 0
        }
        return calendar.date(from: dateComponents)
    }

    static func parseDuration(_ rawValue: String) -> TimeInterval? {
        var value = GuidedComposerNormalization.text(rawValue)
        guard !value.isEmpty else { return nil }
        if value == "an hour" || value == "one hour" {
            return 60 * 60
        }
        if value == "half an hour" || value == "half hour" {
            return 30 * 60
        }

        value = value
            .replacingOccurrences(of: "hours", with: "h")
            .replacingOccurrences(of: "hour", with: "h")
            .replacingOccurrences(of: "hrs", with: "h")
            .replacingOccurrences(of: "hr", with: "h")
            .replacingOccurrences(of: "minutes", with: "m")
            .replacingOccurrences(of: "minute", with: "m")
            .replacingOccurrences(of: "mins", with: "m")
            .replacingOccurrences(of: "min", with: "m")

        guard let expression = durationExpression else {
            return nil
        }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = expression.firstMatch(in: value, range: range),
              match.range == range else {
            return nil
        }
        let hours = number(in: match.range(at: 1), value: value) ?? 0
        let minutes = number(in: match.range(at: 2), value: value) ?? 0
        let duration = hours * 60 * 60 + minutes * 60
        return duration > 0 ? duration : nil
    }

    static func displayTime(_ date: Date, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    static func normalizedDisplayText(
        for rawValue: String,
        resolvedDate: Date,
        timeZone: TimeZone
    ) -> String {
        let value = GuidedComposerNormalization.text(rawValue)
        let clockPattern = #"^(?:\d{1,2}(?::\d{2})?\s*(?:am|pm)?|noon|midnight)$"#
        if value.range(
            of: clockPattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return displayTime(resolvedDate, timeZone: timeZone)
        }
        return rawValue.isEmpty
            ? displayTime(resolvedDate, timeZone: timeZone)
            : rawValue
    }

    static func displayDateTime(
        _ date: Date,
        timeZone: TimeZone
    ) -> String {
        var style = Date.FormatStyle(
            date: .abbreviated,
            time: .shortened
        )
        style.timeZone = timeZone
        return date.formatted(style)
    }

    static func displayDuration(
        _ duration: TimeInterval,
        locale: Locale = .current
    ) -> String {
        let roundedMinutes = max(1, Int((duration / 60).rounded()))
        let style = Duration.UnitsFormatStyle(
            allowedUnits: [.hours, .minutes],
            width: .abbreviated,
            maximumUnitCount: 2
        ).locale(locale)
        return Duration.seconds(roundedMinutes * 60).formatted(
            style
        )
    }

    static func rolledEndIfNeeded(
        _ end: Date,
        after start: Date,
        hadExplicitDate: Bool,
        timeZone: TimeZone = .current
    ) -> Date {
        guard !hadExplicitDate, end <= start else { return end }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(byAdding: .day, value: 1, to: end) ?? end
    }

    static func isUnqualifiedClock(_ rawValue: String) -> Bool {
        let value = GuidedComposerNormalization.text(rawValue)
        let pattern =
            #"^(?:\d{1,2}(?::\d{2})?\s*(?:am|pm)?|noon|midnight)$"#
        return value.range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func clockComponents(
        _ value: String
    ) -> (hour: Int, minute: Int)? {
        if value == "noon" { return (12, 0) }
        if value == "midnight" { return (0, 0) }

        guard let expression = clockExpression else {
            return nil
        }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = expression.firstMatch(in: value, range: range) else {
            return nil
        }
        guard var hour = integer(in: match.range(at: 1), value: value) else {
            return nil
        }
        let minute = integer(in: match.range(at: 2), value: value) ?? 0
        let meridiem = string(in: match.range(at: 3), value: value)

        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "pm", hour != 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
        } else if !(0...23).contains(hour) {
            return nil
        }
        guard (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    private static func relativeOffset(_ value: String) -> TimeInterval? {
        guard let expression = relativeExpression else {
            return nil
        }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = expression.firstMatch(in: value, range: range),
              let amount = number(in: match.range(at: 1), value: value),
              let unit = string(in: match.range(at: 2), value: value) else {
            return nil
        }
        return unit.hasPrefix("h") ? amount * 60 * 60 : amount * 60
    }

    private static func parseExplicitDate(
        _ value: String,
        timeZone: TimeZone
    ) -> Date? {
        let key = ExplicitDateFormatterKey(
            localeIdentifier: Locale.current.identifier,
            timeZoneIdentifier: timeZone.identifier
        )
        let formatters = explicitDateFormatters[key] ?? {
            let patterns = [
                "yyyy-MM-dd HH:mm",
                "yyyy-MM-dd h:mm a",
                "dd/MM/yyyy HH:mm",
                "MM/dd/yyyy h:mm a",
                "dd.MM.yyyy HH:mm",
                "dd-MM-yyyy HH:mm",
                "d MMM yyyy HH:mm",
                "MMM d yyyy h:mm a",
            ]
            let values = patterns.map { pattern in
                let formatter = DateFormatter()
                formatter.locale = Locale(
                    identifier: key.localeIdentifier
                )
                formatter.timeZone = timeZone
                formatter.dateFormat = pattern
                formatter.isLenient = false
                return formatter
            }
            explicitDateFormatters[key] = values
            return values
        }()
        for formatter in formatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func string(
        in range: NSRange,
        value: String
    ) -> String? {
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: value) else {
            return nil
        }
        return String(value[swiftRange]).lowercased()
    }

    private static func integer(
        in range: NSRange,
        value: String
    ) -> Int? {
        string(in: range, value: value).flatMap(Int.init)
    }

    private static func number(
        in range: NSRange,
        value: String
    ) -> Double? {
        string(in: range, value: value).flatMap(Double.init)
    }

    private struct ExplicitDateFormatterKey: Hashable {
        let localeIdentifier: String
        let timeZoneIdentifier: String
    }
}
