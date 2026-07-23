//
//  WorkoutActivityPresentation.swift
//  Journal
//

import Foundation

nonisolated struct WorkoutActivityPresentation: Equatable, Sendable {
    let name: String
    let systemImageName: String
}

nonisolated enum WorkoutActivityCatalog {
    static let walkingRawValue = 52
    static let runningRawValue = 37

    static func movementKind(for rawValue: Int) -> WorkoutMovementKind {
        rawValue == walkingRawValue || rawValue == runningRawValue
            ? .moving
            : .staticWorkout
    }

    static func presentation(for rawValue: Int) -> WorkoutActivityPresentation {
        switch rawValue {
        case 1: activity("American Football", symbol: "american.football.fill")
        case 2: activity("Archery", symbol: "figure.archery")
        case 3: activity("Australian Football", symbol: "sportscourt.fill")
        case 4: activity("Badminton", symbol: "figure.badminton")
        case 5: activity("Baseball", symbol: "baseball.fill")
        case 6: activity("Basketball", symbol: "basketball.fill")
        case 7: activity("Bowling", symbol: "figure.bowling")
        case 8: activity("Boxing", symbol: "figure.boxing")
        case 9: activity("Climbing", symbol: "figure.climbing")
        case 10: activity("Cricket", symbol: "cricket.ball.fill")
        case 11: activity("Cross Training", symbol: "figure.cross.training")
        case 12: activity("Curling", symbol: "figure.curling")
        case 13: activity("Cycling", symbol: "figure.outdoor.cycle")
        case 14, 15, 77, 78: activity("Dance", symbol: "figure.dance")
        case 16: activity("Elliptical", symbol: "figure.elliptical")
        case 17: activity("Equestrian Sports", symbol: "figure.equestrian.sports")
        case 18: activity("Fencing", symbol: "figure.fencing")
        case 19: activity("Fishing", symbol: "figure.fishing")
        case 20: activity("Functional Strength Training", symbol: "figure.strengthtraining.functional")
        case 21: activity("Golf", symbol: "figure.golf")
        case 22: activity("Gymnastics", symbol: "figure.gymnastics")
        case 23: activity("Handball", symbol: "figure.handball")
        case 24: activity("Hiking", symbol: "figure.hiking")
        case 25: activity("Hockey", symbol: "figure.hockey")
        case 26: activity("Hunting", symbol: "figure.hunting")
        case 27: activity("Lacrosse", symbol: "figure.lacrosse")
        case 28: activity("Martial Arts", symbol: "figure.martial.arts")
        case 29: activity("Mind and Body", symbol: "figure.mind.and.body")
        case 30, 73: activity("Mixed Cardio", symbol: "figure.mixed.cardio")
        case 31: activity("Paddle Sports", symbol: "figure.open.water.swim")
        case 32: activity("Play", symbol: "figure.play")
        case 33, 80: activity("Cooldown", symbol: "figure.cooldown")
        case 34: activity("Racquetball", symbol: "figure.racquetball")
        case 35: activity("Rowing", symbol: "figure.rower")
        case 36: activity("Rugby", symbol: "figure.rugby")
        case runningRawValue: activity("Running", symbol: "figure.run")
        case 38: activity("Sailing", symbol: "figure.sailing")
        case 39: activity("Skating Sports", symbol: "figure.skating")
        case 40: activity("Snow Sports", symbol: "snowflake")
        case 41: activity("Soccer", symbol: "figure.soccer")
        case 42: activity("Softball", symbol: "softball.fill")
        case 43: activity("Squash", symbol: "figure.squash")
        case 44, 68: activity("Stair Climbing", symbol: "figure.stairs")
        case 45: activity("Surfing", symbol: "figure.surfing")
        case 46: activity("Swimming", symbol: "figure.pool.swim")
        case 47: activity("Table Tennis", symbol: "figure.table.tennis")
        case 48: activity("Tennis", symbol: "figure.tennis")
        case 49: activity("Track and Field", symbol: "figure.track.and.field")
        case 50: activity("Traditional Strength Training", symbol: "figure.strengthtraining.traditional")
        case 51: activity("Volleyball", symbol: "figure.volleyball")
        case walkingRawValue: activity("Walking", symbol: "figure.walk")
        case 53: activity("Water Fitness", symbol: "figure.water.fitness")
        case 54: activity("Water Polo", symbol: "figure.waterpolo")
        case 55: activity("Water Sports", symbol: "water.waves")
        case 56: activity("Wrestling", symbol: "figure.wrestling")
        case 57: activity("Yoga", symbol: "figure.yoga")
        case 58: activity("Barre", symbol: "figure.barre")
        case 59: activity("Core Training", symbol: "figure.core.training")
        case 60: activity("Cross-Country Skiing", symbol: "figure.skiing.crosscountry")
        case 61: activity("Downhill Skiing", symbol: "figure.skiing.downhill")
        case 62: activity("Flexibility", symbol: "figure.flexibility")
        case 63: activity("High Intensity Interval Training", symbol: "figure.highintensity.intervaltraining")
        case 64: activity("Jump Rope", symbol: "figure.jumprope")
        case 65: activity("Kickboxing", symbol: "figure.kickboxing")
        case 66: activity("Pilates", symbol: "figure.pilates")
        case 67: activity("Snowboarding", symbol: "figure.snowboarding")
        case 69: activity("Step Training", symbol: "figure.step.training")
        case 70: activity("Wheelchair Walk Pace", symbol: "figure.roll")
        case 71: activity("Wheelchair Run Pace", symbol: "figure.roll.runningpace")
        case 72: activity("Tai Chi", symbol: "figure.tai.chi")
        case 74: activity("Hand Cycling", symbol: "figure.hand.cycling")
        case 75: activity("Disc Sports", symbol: "figure.disc.sports")
        case 76: activity("Fitness Gaming", symbol: "figure.gaming")
        case 79: activity("Pickleball", symbol: "figure.pickleball")
        case 82: activity("Swim Bike Run", symbol: "figure.triathlon")
        case 83: activity("Transition", symbol: "arrow.triangle.swap")
        case 84: activity("Underwater Diving", symbol: "figure.scuba.diving")
        default: activity("Workout", symbol: "figure.mixed.cardio")
        }
    }

    private static func activity(
        _ name: LocalizedStringResource,
        symbol: String
    ) -> WorkoutActivityPresentation {
        WorkoutActivityPresentation(
            name: String(localized: name),
            systemImageName: symbol
        )
    }
}

extension WorkoutReviewField {
    var title: LocalizedStringResource {
        switch self {
        case .place: "Workout Location"
        case .origin: "Origin"
        case .destination: "Destination"
        }
    }
}

enum WorkoutLocationPresentation {
    static func name(place: Place?, location: Location?) -> String {
        if let place {
            return place.name
        }
        if let address = location?.compactAddress,
           !address.isEmpty {
            return address
        }
        if let address = compactFallback(location?.formattedAddress) {
            return address
        }
        guard let location else {
            return String(localized: "Location unavailable")
        }
        return "\(coordinate(location.latitude)), \(coordinate(location.longitude))"
    }

    private static func coordinate(_ value: Double) -> String {
        value.formatted(
            .number.precision(.fractionLength(0...5))
        )
    }

    private static func compactFallback(_ address: String?) -> String? {
        guard let address else { return nil }
        let parts = address.split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.prefix(2).joined(separator: ", ")
    }
}
