//
//  PlaceVisitStatisticsService.swift
//  Journal
//

import Foundation
import SwiftData

struct PlaceVisitStatistics: Equatable, Sendable {
    var visitCount: Int = 0
    var lastVisitedAt: Date?
}

@MainActor
enum PlaceVisitStatisticsService {
    static func fetch(in modelContext: ModelContext) throws -> [UUID: PlaceVisitStatistics] {
        let descriptor = FetchDescriptor<LogEntry>()
        return calculate(from: try modelContext.fetch(descriptor))
    }

    static func calculate(from entries: [LogEntry]) -> [UUID: PlaceVisitStatistics] {
        var result: [UUID: PlaceVisitStatistics] = [:]

        for entry in entries where entry.kind == .placeVisit {
            guard entry.entryKindReviewReason == nil,
                  let details = entry.placeVisitDetails,
                  details.review(for: .place) == nil,
                  let place = details.place else {
                continue
            }

            var statistics = result[place.id, default: PlaceVisitStatistics()]
            statistics.visitCount += 1
            if let visitDate = entry.endTime ?? entry.startTime,
               statistics.lastVisitedAt.map({ visitDate > $0 }) ?? true {
                statistics.lastVisitedAt = visitDate
            }
            result[place.id] = statistics
        }

        return result
    }
}
