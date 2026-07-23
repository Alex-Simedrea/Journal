//
//  TimelineProjection.swift
//  Journal
//

import CoreLocation
import Foundation

struct TimelineDayKey: Hashable, Identifiable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    var id: String { "\(year)-\(month)-\(day)" }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 1
        month = components.month ?? 1
        day = components.day ?? 1
    }

    static func today(
        now: Date = .now,
        timeZone: TimeZone = .current
    ) -> TimelineDayKey {
        TimelineDayKey(date: now, timeZone: timeZone)
    }

    func addingDays(_ value: Int) -> TimelineDayKey {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              let movedDate = calendar.date(byAdding: .day, value: value, to: date) else {
            return self
        }
        return TimelineDayKey(date: movedDate, timeZone: calendar.timeZone)
    }

    func dateInterval(in timeZone: TimeZone) -> DateInterval? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let nextDay = addingDays(1)
        let startComponents = DateComponents(year: year, month: month, day: day)
        let endComponents = DateComponents(
            year: nextDay.year,
            month: nextDay.month,
            day: nextDay.day
        )
        guard let start = calendar.date(from: startComponents),
              let end = calendar.date(from: endComponents) else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    func displayDate(in timeZone: TimeZone = .current) -> Date {
        dateInterval(in: timeZone)?.start ?? .now
    }

    var conservativeQueryWindow: DateInterval {
        let earliestZone = TimeZone(secondsFromGMT: 14 * 60 * 60) ?? .gmt
        let latestZone = TimeZone(secondsFromGMT: -12 * 60 * 60) ?? .gmt
        let earliestStart = dateInterval(in: earliestZone)?.start ?? .distantPast
        let latestEnd = dateInterval(in: latestZone)?.end ?? .distantFuture
        return DateInterval(start: earliestStart, end: latestEnd)
    }
}

enum TimelineOccurrenceRole: String, Hashable, Sendable {
    case intervalDay
    case crossZoneArrival
    case unresolvedReview
    case wakeUp
}

struct TimelineOccurrenceID: Hashable, Sendable {
    let entryID: UUID
    let day: TimelineDayKey
    let timeZoneIdentifier: String
    let role: TimelineOccurrenceRole
}

struct TimelineLocationSnapshot: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let systemImage: PlaceSystemImage
    let accuracyRadiusMeters: Double
    let radiusCenterLatitude: Double?
    let radiusCenterLongitude: Double?

    init(
        place: Place?,
        fallbackName: String,
        fallbackLocation: Location?,
        fallbackSystemImage: PlaceSystemImage = .mappin
    ) {
        let location = fallbackLocation ?? place?.location
        name = place?.name ?? fallbackName
        latitude = location?.latitude ?? 0
        longitude = location?.longitude ?? 0
        systemImage = place?.systemImage ?? fallbackSystemImage
        accuracyRadiusMeters = max(place?.accuracyRadiusMeters ?? 0, 0)
        radiusCenterLatitude = place?.location.latitude
        radiusCenterLongitude = place?.location.longitude
        if let place {
            id = place.id.uuidString
        } else if let location {
            id = "\(fallbackName)-\(location.latitude)-\(location.longitude)"
        } else {
            id = "unresolved-\(fallbackName)"
        }
    }

    var hasCoordinate: Bool {
        (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
            && !(latitude == 0 && longitude == 0)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var radiusCenterCoordinate: CLLocationCoordinate2D? {
        guard let radiusCenterLatitude, let radiusCenterLongitude else {
            return nil
        }
        return CLLocationCoordinate2D(
            latitude: radiusCenterLatitude,
            longitude: radiusCenterLongitude
        )
    }
}

struct TimelinePersonSnapshot: Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let contactIdentifier: String?
}

enum TimelineReviewTarget: String, Hashable, Sendable {
    case entryKind
    case transitType
    case origin
    case destination
    case place
    case time
    case people
}

struct TimelineReviewSnapshot: Hashable, Identifiable, Sendable {
    let target: TimelineReviewTarget
    let reason: String

    var id: String { "\(target.rawValue)-\(reason)" }
}
