import Foundation
import Testing

@testable import Journal

@Suite("Home day summaries")
@MainActor
struct DaySummaryTests {
    private let bucharest = "Europe/Bucharest"

    @Test("Candidate days include intervals and unresolved creation days")
    func candidateDays() {
        let resolved = snapshot(
            createdAt: date("2026-07-12T09:00:00+03:00"),
            start: date("2026-07-12T23:00:00+03:00"),
            end: date("2026-07-14T01:00:00+03:00")
        )
        let unresolved = snapshot(
            createdAt: date("2026-07-16T09:00:00+03:00"),
            start: nil,
            end: nil,
            needsReview: true
        )

        #expect(
            DaySummaryProjector.candidateDays(for: [resolved, unresolved])
                == [day(12), day(13), day(14), day(16)]
        )
    }

    @Test("Nearest-day ties prefer the following day")
    func nearestDayPrefersNext() {
        #expect(
            DaySummaryProjector.nearestDay(
                to: day(13),
                in: [day(12), day(14)]
            ) == day(14)
        )
    }

    @Test("Summaries remain chronological regardless of entry order")
    func chronologicalOrdering() {
        let later = snapshot(
            createdAt: date("2026-07-14T09:00:00+03:00"),
            start: date("2026-07-14T09:00:00+03:00"),
            end: date("2026-07-14T10:00:00+03:00")
        )
        let earlier = snapshot(
            createdAt: date("2026-07-12T09:00:00+03:00"),
            start: date("2026-07-12T09:00:00+03:00"),
            end: date("2026-07-12T10:00:00+03:00")
        )

        #expect(
            DaySummaryProjector.makeSummaries(entries: [later, earlier])
                .map(\.day) == [day(12), day(14)]
        )
    }

    @Test("Date labels include the year only outside the current year")
    func dateLabels() {
        let now = date("2026-07-31T12:00:00+03:00")
        let title = DaySummaryDatePresentation.dayTitle(
            for: day(12),
            now: now
        )
        #expect(title == "Sunday, July 12")
        #expect(!title.contains("2026"))
        #expect(
            DaySummaryDatePresentation.monthTitle(
                for: TimelineDayKey(year: 2025, month: 7, day: 12),
                now: now
            ).contains("2025")
        )
    }

    @Test("Movement combines transit and moving workout metrics")
    func movementAggregation() throws {
        let transit = snapshot(
            createdAt: date("2026-07-12T08:00:00+03:00"),
            start: date("2026-07-12T08:00:00+03:00"),
            end: date("2026-07-12T09:00:00+03:00"),
            kind: .transit,
            transitDistance: 10_000
        )
        let workout = snapshot(
            createdAt: date("2026-07-12T10:00:00+03:00"),
            start: date("2026-07-12T10:00:00+03:00"),
            end: date("2026-07-12T10:30:00+03:00"),
            kind: .workout,
            workoutMovementKind: .moving,
            workoutDistance: 4_000
        )

        let summary = try #require(
            DaySummaryProjector.makeSummaries(entries: [transit, workout])
                .first
        )
        let movement = try #require(summary.movement)
        #expect(movement.icons.count == 2)
        #expect(movement.distanceMeters == 14_000)
        #expect(movement.durationSeconds == 5_400)
        #expect(summary.showsOverviewMap)
    }

    @Test("Movement icons deduplicate repeated transit types")
    func movementIconDeduplication() throws {
        let first = snapshot(
            createdAt: date("2026-07-12T08:00:00+03:00"),
            start: date("2026-07-12T08:00:00+03:00"),
            end: date("2026-07-12T09:00:00+03:00"),
            transitType: "Bolt",
            transitDistance: 5_000
        )
        let repeated = snapshot(
            createdAt: date("2026-07-12T10:00:00+03:00"),
            start: date("2026-07-12T10:00:00+03:00"),
            end: date("2026-07-12T10:30:00+03:00"),
            transitType: "  bolt  ",
            transitDistance: 3_000
        )

        let summary = try #require(
            DaySummaryProjector.makeSummaries(entries: [first, repeated]).first
        )
        let movement = try #require(summary.movement)
        #expect(movement.icons.count == 1)
        #expect(movement.distanceMeters == 8_000)
        #expect(movement.durationSeconds == 5_400)
    }

    @Test("Repeated workout activities count as one movement type")
    func workoutMovementIconDeduplication() throws {
        let first = snapshot(
            createdAt: date("2026-07-12T08:00:00+03:00"),
            start: date("2026-07-12T08:00:00+03:00"),
            end: date("2026-07-12T09:00:00+03:00"),
            kind: .workout,
            workoutMovementKind: .moving,
            workoutSystemImageName: "figure.walk"
        )
        let repeated = snapshot(
            createdAt: date("2026-07-12T10:00:00+03:00"),
            start: date("2026-07-12T10:00:00+03:00"),
            end: date("2026-07-12T10:30:00+03:00"),
            kind: .workout,
            workoutMovementKind: .moving,
            workoutSystemImageName: "figure.walk"
        )

        let summary = try #require(
            DaySummaryProjector.makeSummaries(entries: [first, repeated]).first
        )
        #expect(summary.movement?.icons.count == 1)
    }

    @Test("Longest stationary occurrence becomes featured place")
    func featuredPlace() throws {
        let short = snapshot(
            createdAt: date("2026-07-12T08:00:00+03:00"),
            start: date("2026-07-12T08:00:00+03:00"),
            end: date("2026-07-12T09:00:00+03:00"),
            kind: .placeVisit,
            visitLocation: location("Cafe", latitude: 45.1)
        )
        let long = snapshot(
            createdAt: date("2026-07-12T10:00:00+03:00"),
            start: date("2026-07-12T10:00:00+03:00"),
            end: date("2026-07-12T13:00:00+03:00"),
            kind: .workout,
            workoutMovementKind: .staticWorkout,
            workoutLocation: location("Gym", latitude: 45.2)
        )

        let summary = try #require(
            DaySummaryProjector.makeSummaries(entries: [short, long]).first
        )
        #expect(summary.featuredPlace?.location.name == "Gym")
        #expect(summary.weatherRequest?.latitude == 45.2)
    }

    @Test("A lone stationary place anchors weather without a duplicate tile")
    func singlePlaceIsNotFeatured() throws {
        let visit = snapshot(
            createdAt: date("2026-07-12T10:00:00+03:00"),
            start: date("2026-07-12T10:00:00+03:00"),
            end: date("2026-07-12T13:00:00+03:00"),
            kind: .placeVisit,
            visitLocation: location("Only place", latitude: 45.3)
        )

        let summary = try #require(
            DaySummaryProjector.makeSummaries(entries: [visit]).first
        )
        #expect(summary.featuredPlace == nil)
        #expect(summary.weatherRequest?.latitude == 45.3)
    }

    @Test("People and photos preserve unique first-seen order")
    func deduplication() throws {
        let firstPerson = TimelinePersonSnapshot(
            id: UUID(),
            name: "First",
            contactIdentifier: nil
        )
        let secondPerson = TimelinePersonSnapshot(
            id: UUID(),
            name: "Second",
            contactIdentifier: nil
        )
        let firstPhoto = PhotoReference(assetLocalIdentifier: "first")
        let secondPhoto = PhotoReference(assetLocalIdentifier: "second")
        let first = snapshot(
            createdAt: date("2026-07-12T08:00:00+03:00"),
            start: date("2026-07-12T08:00:00+03:00"),
            end: date("2026-07-12T09:00:00+03:00"),
            people: [firstPerson],
            photos: [firstPhoto]
        )
        let second = snapshot(
            createdAt: date("2026-07-12T10:00:00+03:00"),
            start: date("2026-07-12T10:00:00+03:00"),
            end: date("2026-07-12T11:00:00+03:00"),
            people: [firstPerson, secondPerson],
            photos: [firstPhoto, secondPhoto]
        )

        let summary = try #require(
            DaySummaryProjector.makeSummaries(entries: [second, first]).first
        )
        #expect(summary.people.map(\.name) == ["First", "Second"])
        #expect(summary.photos.map(\.id) == [firstPhoto.id, secondPhoto.id])
    }

    @Test("Wake-up remains visible in every content density")
    func wakeUpAlwaysRemainsVisible() {
        let dense = summary(
            photoCount: 3,
            hasPeople: true,
            hasMovement: true,
            hasFeaturedPlace: true
        )
        #expect(DaySummaryLayoutRecipe.showsWakeUp(in: dense))

        let sparse = summary(
            photoCount: 2,
            hasPeople: true,
            hasMovement: true,
            hasFeaturedPlace: true
        )
        #expect(DaySummaryLayoutRecipe.showsWakeUp(in: sparse))
    }

    @Test("Three distinct movement types require the expanded tile")
    func distinctMovementTypesExpandMovement() {
        let recipe = DaySummaryLayoutRecipe.make(
            for: summary(
                photoCount: 0,
                hasPeople: false,
                hasMovement: true,
                hasFeaturedPlace: false,
                hasWakeUp: false,
                movementTypeCount: 3
            )
        )

        #expect((pixelFrame(.movement, in: recipe)?.height ?? 0) >= 75)
    }

    @Test("Wake-up stays compact while movement balances the short day")
    func compactWakeLayout() {
        let recipe = DaySummaryLayoutRecipe.make(
            for: summary(
                photoCount: 0,
                hasPeople: false,
                hasMovement: true,
                hasFeaturedPlace: false
            )
        )

        #expect(recipe.variant == .overviewThreeColumn)
        #expect(recipe.referenceHeight == 91)
        #expect(pixelFrame(.weather, in: recipe)?.height == 45)
        #expect(pixelFrame(.wakeUp, in: recipe)?.x == 159)
        #expect(pixelFrame(.wakeUp, in: recipe)?.height == 38)
        #expect(
            abs((pixelFrame(.wakeUp, in: recipe)?.y ?? 0) - 53)
                < 0.001
        )
        #expect(pixelFrame(.movement, in: recipe)?.x == 274)
        #expect(pixelFrame(.movement, in: recipe)?.height == 91)
        #expect(pixelFrame(.overview, in: recipe)?.height == 91)
    }

    @Test("People stay compact while movement balances their column")
    func compactPeopleLayout() {
        let recipe = DaySummaryLayoutRecipe.make(
            for: summary(
                photoCount: 0,
                hasPeople: true,
                hasMovement: true,
                hasFeaturedPlace: false,
                hasWakeUp: false
            )
        )

        #expect(recipe.referenceHeight == 103)
        #expect(pixelFrame(.weather, in: recipe)?.height == 45)
        #expect(pixelFrame(.people, in: recipe)?.height == 50)
        #expect(pixelFrame(.movement, in: recipe)?.x == 274)
        #expect(
            abs((pixelFrame(.movement, in: recipe)?.height ?? 0) - 103)
                < 0.001
        )
    }

    @Test("Two photos balance a compact weather and movement stack")
    func compactPhotoLayout() {
        let recipe = DaySummaryLayoutRecipe.make(
            for: summary(
                photoCount: 2,
                hasPeople: false,
                hasMovement: true,
                hasFeaturedPlace: false,
                hasWakeUp: false
            )
        )

        #expect(recipe.referenceHeight == 90)
        #expect(pixelFrame(.weather, in: recipe)?.height == 45)
        #expect(pixelFrame(.movement, in: recipe)?.height == 37)
        #expect(pixelFrame(.photos, in: recipe)?.height == 90)
    }

    @Test("A retained featured place keeps two photos to one compact row")
    func compactPhotosWithFeaturedPlace() {
        let recipe = DaySummaryLayoutRecipe.make(
            for: summary(
                photoCount: 2,
                hasPeople: false,
                hasMovement: true,
                hasFeaturedPlace: true,
                hasWakeUp: false
            )
        )

        #expect(recipe.referenceHeight == 128)
        #expect(
            abs((pixelFrame(.photos, in: recipe)?.height ?? 0) - 49)
                < 0.001
        )
        #expect(pixelFrame(.featuredPlace, in: recipe)?.height == 71)
        #expect(
            abs((pixelFrame(.featuredPlace, in: recipe)?.y ?? 0) - 57)
                < 0.001
        )
    }

    @Test("Content-heavy days retain the full dense height")
    func denseLayout() {
        let recipe = DaySummaryLayoutRecipe.make(
            for: summary(
                photoCount: 4,
                hasPeople: true,
                hasMovement: true,
                hasFeaturedPlace: true,
                hasWakeUp: false
            )
        )

        #expect(recipe.referenceHeight == 186)
        #expect(pixelFrame(.people, in: recipe)?.height == 50)
        #expect(
            abs((pixelFrame(.photos, in: recipe)?.height ?? 0) - 107)
                < 0.001
        )
        #expect(pixelFrame(.featuredPlace, in: recipe)?.height == 71)
    }

    @Test("Rich days promote weather, movement, and the featured place")
    func richDenseLayout() {
        let recipe = DaySummaryLayoutRecipe.make(
            for: summary(
                photoCount: 4,
                hasPeople: true,
                hasMovement: true,
                hasFeaturedPlace: true,
                hasWakeUp: true,
                movementTypeCount: 3
            )
        )

        #expect(recipe.referenceHeight == 231)
        #expect(pixelFrame(.weather, in: recipe)?.height == 90)
        #expect(pixelFrame(.movement, in: recipe)?.height == 75)
        #expect(pixelFrame(.wakeUp, in: recipe)?.height == 38)
        #expect(
            abs((pixelFrame(.featuredPlace, in: recipe)?.height ?? 0) - 81)
                < 0.001
        )
    }

    @Test("Unresolved-only summaries use the review recipe")
    func reviewLayout() {
        let base = summary(
            photoCount: 0,
            hasPeople: false,
            hasMovement: false,
            hasFeaturedPlace: false,
            hasWakeUp: false
        )
        let review = DaySummary(
            day: base.day,
            occurrences: base.occurrences,
            overviewData: base.overviewData,
            showsOverviewMap: false,
            people: [],
            peopleNeedReview: false,
            photos: [],
            movement: nil,
            wakeUp: nil,
            featuredPlace: nil,
            weatherRequest: nil,
            needsReview: true,
            showsNeedsReviewPlaceholder: true
        )
        #expect(
            DaySummaryLayoutRecipe.make(for: review).variant == .review
        )
    }

    @Test("Unresolved entries remain reachable as review summaries")
    func unresolvedProjection() throws {
        let unresolved = snapshot(
            createdAt: date("2026-07-12T09:00:00+03:00"),
            start: nil,
            end: nil,
            needsReview: true,
            kind: .wakeUp
        )
        let summary = try #require(
            DaySummaryProjector.makeSummaries(entries: [unresolved]).first
        )
        #expect(summary.showsNeedsReviewPlaceholder)
        #expect(summary.needsReview)
    }

    @Test("Day weather enrichment maps into row state")
    @MainActor
    func weatherEnrichment() async throws {
        let summary = summary(
            photoCount: 0,
            hasPeople: false,
            hasMovement: false,
            hasFeaturedPlace: true,
            hasWakeUp: false
        )
        let expected = DayWeatherSummary(
            condition: "clear",
            symbolName: "sun.max.fill",
            highTemperatureCelsius: 31,
            maximumHumidity: 0.7,
            date: date("2026-07-12T12:00:00+03:00")
        )
        let row = DaySummaryRowModel(summary: summary)
        await row.loadEnrichment(
            weatherClient: StubDayWeatherClient(result: expected),
            routeClient: StubDayWorkoutRouteClient()
        )
        #expect(row.weatherState == .loaded(expected))
    }

    @Test("Daily weather presentation is anchored in local daytime")
    func dailyWeatherPresentationDate() {
        let request = DayWeatherRequest(
            day: day(12),
            startDate: date("2026-07-12T00:00:00+03:00"),
            endDate: date("2026-07-13T00:00:00+03:00"),
            latitude: 44.43,
            longitude: 26.10,
            timeZoneIdentifier: bucharest
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: bucharest) ?? .current

        #expect(calendar.component(.hour, from: request.presentationDate) == 12)
        #expect(
            WeatherPresentation.skyPhase(
                date: request.presentationDate,
                latitude: request.latitude,
                longitude: request.longitude,
                symbolName: "sun.max.fill",
                timeZone: calendar.timeZone
            ) == .day
        )
    }

    @Test("Concurrent daily weather requests share one load and cache it")
    func weatherCaching() async throws {
        let counter = InvocationCounter()
        let expected = DayWeatherSummary(
            condition: "clear",
            symbolName: "sun.max.fill",
            highTemperatureCelsius: 31,
            maximumHumidity: 0.7,
            date: date("2026-07-12T12:00:00+03:00")
        )
        let client = WeatherKitDayClient { _ in
            await counter.increment()
            await Task.yield()
            return expected
        }
        let request = try #require(
            summary(
                photoCount: 0,
                hasPeople: false,
                hasMovement: false,
                hasFeaturedPlace: true
            ).weatherRequest
        )

        async let first = client.weather(for: request)
        async let second = client.weather(for: request)
        let concurrent = try await (first, second)
        let cached = try await client.weather(for: request)

        #expect(concurrent.0 == expected)
        #expect(concurrent.1 == expected)
        #expect(cached == expected)
        #expect(await counter.value == 1)
    }

    private func summary(
        photoCount: Int,
        hasPeople: Bool,
        hasMovement: Bool,
        hasFeaturedPlace: Bool,
        hasWakeUp: Bool = true,
        movementTypeCount: Int = 1
    ) -> DaySummary {
        let place = location("Place", latitude: 45.1)
        return DaySummary(
            day: day(12),
            occurrences: [],
            overviewData: TimelineOverviewData(),
            showsOverviewMap: hasMovement,
            people: hasPeople
                ? [TimelinePersonSnapshot(id: UUID(), name: "E", contactIdentifier: nil)]
                : [],
            peopleNeedReview: false,
            photos: (0..<photoCount).map {
                PhotoReference(assetLocalIdentifier: "photo-\($0)")
            },
            movement: hasMovement
                ? DayMovementSummary(
                    icons: (0..<movementTypeCount).map { index in
                        DayMovementIcon(
                            id: TimelineOccurrenceID(
                                entryID: UUID(),
                                day: day(12),
                                timeZoneIdentifier: bucharest,
                                role: .intervalDay
                            ),
                            kind: .transit("Type \(index)")
                        )
                    },
                    distanceMeters: nil,
                    durationSeconds: nil,
                    needsReview: false
                )
                : nil,
            wakeUp: hasWakeUp
                ? DayWakeSummary(
                    wakeTime: date("2026-07-12T08:00:00+03:00"),
                    durationSeconds: 8 * 60 * 60,
                    timeZoneIdentifier: bucharest
                )
                : nil,
            featuredPlace: hasFeaturedPlace
                ? DayFeaturedPlace(
                    occurrenceID: TimelineOccurrenceID(
                        entryID: UUID(),
                        day: day(12),
                        timeZoneIdentifier: bucharest,
                        role: .intervalDay
                    ),
                    location: place,
                    durationSeconds: 3_600,
                    timeZoneIdentifier: bucharest,
                    needsReview: false
                )
                : nil,
            weatherRequest: DayWeatherRequest(
                day: day(12),
                startDate: date("2026-07-12T00:00:00+03:00"),
                endDate: date("2026-07-13T00:00:00+03:00"),
                latitude: place.latitude,
                longitude: place.longitude,
                timeZoneIdentifier: bucharest
            ),
            needsReview: false,
            showsNeedsReviewPlaceholder: false
        )
    }

    private struct PixelFrame {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    private func pixelFrame(
        _ tile: DaySummaryTileKind,
        in recipe: DaySummaryLayoutRecipe
    ) -> PixelFrame? {
        guard let frame = recipe.placements.first(where: {
            $0.tile == tile
        })?.frame else {
            return nil
        }
        return PixelFrame(
            x: frame.x * DaySummaryLayoutRecipe.referenceWidth,
            y: frame.y * DaySummaryLayoutRecipe.referenceWidth,
            width: frame.width * DaySummaryLayoutRecipe.referenceWidth,
            height: frame.height * DaySummaryLayoutRecipe.referenceWidth
        )
    }

    private func snapshot(
        createdAt: Date,
        start: Date?,
        end: Date?,
        needsReview: Bool = false,
        kind: LogKind = .transit,
        transitType: String = "Transit",
        transitDistance: Double? = nil,
        visitLocation: TimelineLocationSnapshot? = nil,
        people: [TimelinePersonSnapshot] = [],
        photos: [PhotoReference] = [],
        workoutMovementKind: WorkoutMovementKind? = nil,
        workoutSystemImageName: String = "figure.mixed.cardio",
        workoutDistance: Double? = nil,
        workoutLocation: TimelineLocationSnapshot? = nil
    ) -> TimelineEntrySnapshot {
        TimelineEntrySnapshot(
            createdAt: createdAt,
            startTime: start,
            endTime: end,
            startTimeZoneIdentifier: bucharest,
            endTimeZoneIdentifier: bucharest,
            creationTimeZoneIdentifier: bucharest,
            timeConfidence: start == nil || end == nil
                ? .unresolved
                : .explicit,
            needsReview: needsReview,
            kind: kind,
            transitType: transitType,
            transitDistanceMeters: transitDistance,
            visitLocation: visitLocation,
            people: people,
            photoReferences: photos,
            workoutSystemImageName: workoutSystemImageName,
            workoutMovementKind: workoutMovementKind,
            workoutDistanceMeters: workoutDistance,
            workoutPlaceLocation: workoutLocation
        )
    }

    private func location(
        _ name: String,
        latitude: Double
    ) -> TimelineLocationSnapshot {
        TimelineLocationSnapshot(
            name: name,
            latitude: latitude,
            longitude: 25
        )
    }

    private func day(_ value: Int) -> TimelineDayKey {
        TimelineDayKey(year: 2026, month: 7, day: value)
    }

    private func date(_ value: String) -> Date {
        do {
            return try Date(value, strategy: .iso8601)
        } catch {
            Issue.record("Could not parse test date: \(value)")
            return .distantPast
        }
    }
}

private actor InvocationCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private struct StubDayWeatherClient: DayWeatherProviding {
    let result: DayWeatherSummary

    func weather(for request: DayWeatherRequest) async throws
        -> DayWeatherSummary {
        result
    }
}

private struct StubDayWorkoutRouteClient: DayWorkoutRouteProviding {
    func route(for workoutUUID: UUID) async throws
        -> [WorkoutCoordinateSnapshot] {
        []
    }
}
