import Foundation
import CoreLocation
import Testing

@testable import Journal

@Suite("Home period summaries")
@MainActor
struct PeriodSummaryTests {
    private let timeZone = "Europe/Bucharest"

    @Test("Entries are attributed once to their local start period")
    func singleAttribution() throws {
        let entry = snapshot(
            start: date("2026-07-31T23:30:00+03:00"),
            end: date("2026-08-01T02:00:00+03:00")
        )
        let days = DaySummaryProjector.makeSummaries(entries: [entry])
        let months = PeriodSummaryProjector.makeMonthSummaries(
            entries: [entry],
            daySummaries: days
        )

        #expect(months.count == 1)
        #expect(months.first?.monthKey == MonthKey(year: 2026, month: 7))
        #expect(months.first?.entryCount == 1)
    }

    @Test("Month and year summaries stay chronological")
    func chronologicalPeriods() {
        let july = snapshot(
            start: date("2026-07-04T10:00:00+03:00"),
            end: date("2026-07-04T11:00:00+03:00")
        )
        let january = snapshot(
            start: date("2025-01-04T10:00:00+02:00"),
            end: date("2025-01-04T11:00:00+02:00")
        )
        let entries = [july, january]
        let days = DaySummaryProjector.makeSummaries(entries: entries)

        #expect(
            PeriodSummaryProjector.makeMonthSummaries(
                entries: entries,
                daySummaries: days
            ).compactMap(\.monthKey) == [
                MonthKey(year: 2025, month: 1),
                MonthKey(year: 2026, month: 7),
            ]
        )
        #expect(
            PeriodSummaryProjector.makeYearSummaries(
                entries: entries,
                daySummaries: days
            ).compactMap(\.yearKey) == [YearKey(year: 2025), YearKey(year: 2026)]
        )
    }

    @Test("People ranking unions overlapping logged intervals")
    func peopleDurationUnion() throws {
        let person = TimelinePersonSnapshot(
            id: UUID(),
            name: "Emma",
            contactIdentifier: nil
        )
        let first = snapshot(
            start: date("2026-07-04T10:00:00+03:00"),
            end: date("2026-07-04T12:00:00+03:00"),
            people: [person]
        )
        let second = snapshot(
            start: date("2026-07-04T11:00:00+03:00"),
            end: date("2026-07-04T13:00:00+03:00"),
            people: [person]
        )
        let entries = [first, second]
        let summary = try #require(
            PeriodSummaryProjector.makeMonthSummaries(
                entries: entries,
                daySummaries: DaySummaryProjector.makeSummaries(entries: entries)
            ).first
        )

        #expect(
            abs((summary.people.first?.loggedDuration ?? 0) - 10_800) < 0.001
        )
        #expect(summary.people.first?.entryCount == 2)
        #expect(summary.people.first?.dayCount == 1)
    }

    @Test("Frequent routes combine both directions")
    func bidirectionalRoutes() throws {
        let home = location("Home", latitude: 44.18, longitude: 28.61)
        let beach = location("Beach", latitude: 44.25, longitude: 28.63)
        let outbound = snapshot(
            start: date("2026-07-04T10:00:00+03:00"),
            end: date("2026-07-04T11:00:00+03:00"),
            origin: home,
            destination: beach
        )
        let inbound = snapshot(
            start: date("2026-07-05T10:00:00+03:00"),
            end: date("2026-07-05T11:00:00+03:00"),
            origin: beach,
            destination: home
        )
        let entries = [outbound, inbound]
        let summary = try #require(
            PeriodSummaryProjector.makeMonthSummaries(
                entries: entries,
                daySummaries: DaySummaryProjector.makeSummaries(entries: entries)
            ).first
        )

        #expect(summary.frequentRoute?.count == 2)
        #expect(summary.overviewData.pathDisplayMode == .visibleAtMapScale)
        #expect(Set(summary.overviewData.markers.map(\.name)) == [
            "Home",
            "Beach",
        ])
    }

    @Test("A period with multiple cities shows one marker per city")
    func periodCityMarkers() throws {
        let home = location(
            "Home",
            latitude: 44.4268,
            longitude: 26.1025,
            city: "Bucharest"
        )
        let cafe = location(
            "Cafe",
            latitude: 44.4378,
            longitude: 26.0969,
            city: "Bucharest"
        )
        let hotel = location(
            "Hotel",
            latitude: 48.8566,
            longitude: 2.3522,
            city: "Paris"
        )
        let museum = location(
            "Museum",
            latitude: 48.8606,
            longitude: 2.3376,
            city: "Paris"
        )
        let entries = [
            snapshot(
                start: date("2026-07-04T10:00:00+03:00"),
                end: date("2026-07-04T13:00:00+03:00"),
                origin: home,
                destination: hotel
            ),
            snapshot(
                start: date("2026-07-05T10:00:00+03:00"),
                end: date("2026-07-05T13:00:00+03:00"),
                origin: cafe,
                destination: museum
            ),
        ]
        let summary = try #require(
            PeriodSummaryProjector.makeMonthSummaries(
                entries: entries,
                daySummaries: DaySummaryProjector.makeSummaries(
                    entries: entries
                )
            ).first
        )

        #expect(Set(summary.overviewData.markers.map(\.name)) == [
            "Bucharest",
            "Paris",
        ])
        #expect(summary.overviewData.markers.allSatisfy {
            $0.systemImage == .buildings
        })
    }

    @Test("A period with one city keeps its individual place markers")
    func singleCityPlaceMarkers() throws {
        let home = location(
            "Home",
            latitude: 44.4268,
            longitude: 26.1025,
            city: "Bucharest"
        )
        let work = location(
            "Work",
            latitude: 44.4378,
            longitude: 26.0969,
            city: "Bucharest"
        )
        let entries = [snapshot(
            start: date("2026-07-04T10:00:00+03:00"),
            end: date("2026-07-04T11:00:00+03:00"),
            origin: home,
            destination: work
        )]
        let summary = try #require(
            PeriodSummaryProjector.makeMonthSummaries(
                entries: entries,
                daySummaries: DaySummaryProjector.makeSummaries(
                    entries: entries
                )
            ).first
        )

        #expect(Set(summary.overviewData.markers.map(\.name)) == [
            "Home",
            "Work",
        ])
    }

    @Test("Longest journey requires at least one hundred kilometers")
    func longestJourneyThreshold() throws {
        let short = snapshot(
            start: date("2026-07-04T10:00:00+03:00"),
            end: date("2026-07-04T11:00:00+03:00"),
            distance: 99_999
        )
        let long = snapshot(
            start: date("2026-07-05T10:00:00+03:00"),
            end: date("2026-07-05T11:00:00+03:00"),
            distance: 100_000
        )

        let shortSummary = try #require(
            PeriodSummaryProjector.makeMonthSummaries(
                entries: [short],
                daySummaries: DaySummaryProjector.makeSummaries(entries: [short])
            ).first
        )
        let longSummary = try #require(
            PeriodSummaryProjector.makeMonthSummaries(
                entries: [long],
                daySummaries: DaySummaryProjector.makeSummaries(entries: [long])
            ).first
        )

        #expect(shortSummary.longestJourney == nil)
        #expect(longSummary.longestJourney?.distanceMeters == 100_000)
    }

    @Test("Period masonry produces bounded non-overlapping frames")
    func layoutFrames() {
        let recipe = PeriodSummaryLayoutRecipe.make(for: .layoutFixture)
        #expect(recipe.isCompletelyFilled)
        #expect(recipe == PeriodSummaryLayoutRecipe.make(for: .layoutFixture))
        for placement in recipe.placements {
            #expect(placement.frame.x >= 0)
            #expect(placement.frame.y >= 0)
            #expect(placement.frame.x + placement.frame.width <= 1.001)
            #expect(
                (placement.frame.y + placement.frame.height)
                    * PeriodSummaryLayoutRecipe.referenceWidth
                    <= recipe.referenceHeight + 0.001
            )
        }
        for lhs in recipe.placements {
            for rhs in recipe.placements where lhs.id.rawValue < rhs.id.rawValue {
                let intersects = lhs.frame.x < rhs.frame.x + rhs.frame.width
                    && lhs.frame.x + lhs.frame.width > rhs.frame.x
                    && lhs.frame.y < rhs.frame.y + rhs.frame.height
                    && lhs.frame.y + lhs.frame.height > rhs.frame.y
                #expect(!intersects)
            }
        }
    }

    @Test("Month layout hides a lone country and redundant counters")
    func compactMonthTileSelection() {
        let tiles = Set(
            PeriodSummaryLayoutRecipe.make(for: .layoutFixture)
                .placements.map(\.tile)
        )

        #expect(tiles == [
            .overview,
            .people,
            .cities,
            .activity,
            .busiestDay,
        ])
    }

    @Test("Dense period layout is deterministic and completely filled")
    func denseLayout() {
        let first = PeriodSummaryLayoutRecipe.make(for: .galleryPreview)
        let second = PeriodSummaryLayoutRecipe.make(for: .galleryPreview)

        #expect(first == second)
        #expect(first.isCompletelyFilled)
    }

    private func snapshot(
        start: Date,
        end: Date,
        people: [TimelinePersonSnapshot] = [],
        origin: TimelineLocationSnapshot? = nil,
        destination: TimelineLocationSnapshot? = nil,
        distance: Double = 10_000
    ) -> TimelineEntrySnapshot {
        TimelineEntrySnapshot(
            createdAt: start,
            startTime: start,
            endTime: end,
            startTimeZoneIdentifier: timeZone,
            endTimeZoneIdentifier: timeZone,
            creationTimeZoneIdentifier: timeZone,
            timeConfidence: .explicit,
            kind: .transit,
            transitType: "Car",
            transitDistanceMeters: distance,
            originLocation: origin,
            destinationLocation: destination,
            people: people
        )
    }

    private func location(
        _ name: String,
        latitude: Double,
        longitude: Double,
        city: String? = nil
    ) -> TimelineLocationSnapshot {
        TimelineLocationSnapshot(
            name: name,
            latitude: latitude,
            longitude: longitude,
            cityName: city
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

private extension PeriodSummary {
    static var layoutFixture: PeriodSummary {
        PeriodSummary(
            key: .month(MonthKey(year: 2026, month: 7)),
            days: [],
            entryCount: 20,
            overviewData: TimelineOverviewData(
                markers: [TimelineMapMarker(
                    id: "home",
                    name: "Home",
                    coordinate: .init(latitude: 44, longitude: 28),
                    systemImage: .house
                )]
            ),
            people: [.init(
                person: .init(id: UUID(), name: "Emma", contactIdentifier: nil),
                loggedDuration: 100,
                dayCount: 1,
                entryCount: 1
            )],
            movement: nil,
            frequentRoute: nil,
            mostVisitedPlace: nil,
            cities: [.init(name: "Constanța", code: nil, visitCount: 1)],
            countries: [.init(name: "Romania", code: "RO", visitCount: 1)],
            photos: [],
            totalPhotoCount: 0,
            busiestDay: TimelineDayKey(year: 2026, month: 7, day: 4),
            busiestMonth: nil,
            longestJourney: nil,
            sleep: nil,
            activity: Array(repeating: 1, count: 31),
            reviewCount: 0,
            newGroundCount: 0
        )
    }
}
