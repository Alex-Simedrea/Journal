import CoreLocation
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Journal

@Suite("Guided deterministic composer")
@MainActor
struct GuidedComposerTests {
    private let zone = TimeZone(identifier: "Europe/Bucharest")!

    @Test("Time parsing anchors clocks to the selected day")
    func selectedDayTimeParsing() throws {
        let day = TimelineDayKey(year: 2026, month: 7, day: 18)
        let tenThirty = try #require(
            GuidedComposerTimeParser.parseTime(
                "10:30",
                role: .start,
                selectedDay: day,
                timeZone: zone
            )
        )
        let noon = try #require(
            GuidedComposerTimeParser.parseTime(
                "noon",
                role: .start,
                selectedDay: day,
                timeZone: zone
            )
        )
        let tomorrowAtSix = try #require(
            GuidedComposerTimeParser.parseTime(
                "tomorrow at 6",
                role: .start,
                selectedDay: day,
                timeZone: zone
            )
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        #expect(calendar.component(.year, from: tenThirty) == 2026)
        #expect(calendar.component(.month, from: tenThirty) == 7)
        #expect(calendar.component(.day, from: tenThirty) == 18)
        #expect(calendar.component(.hour, from: tenThirty) == 10)
        #expect(calendar.component(.minute, from: tenThirty) == 30)
        #expect(calendar.component(.hour, from: noon) == 12)
        #expect(calendar.component(.day, from: tomorrowAtSix) == 19)
        #expect(calendar.component(.hour, from: tomorrowAtSix) == 6)
    }

    @Test("Relative times are rejected away from today")
    func relativeTimeDayGuard() {
        let now = date("2026-07-18T10:00:00+03:00")
        let historical = TimelineDayKey(year: 2026, month: 7, day: 17)
        let today = TimelineDayKey(year: 2026, month: 7, day: 18)

        #expect(
            GuidedComposerTimeParser.parseTime(
                "now",
                role: .end,
                selectedDay: historical,
                timeZone: zone,
                now: now
            ) == nil
        )
        #expect(
            GuidedComposerTimeParser.parseTime(
                "30 minutes ago",
                role: .start,
                selectedDay: historical,
                timeZone: zone,
                now: now
            ) == nil
        )
        #expect(
            GuidedComposerTimeParser.parseTime(
                "30 minutes ago",
                role: .start,
                selectedDay: today,
                timeZone: zone,
                now: now
            ) == now.addingTimeInterval(-30 * 60)
        )
    }

    @Test("Durations normalize and unqualified ends roll overnight")
    func durationAndOvernightParsing() throws {
        #expect(GuidedComposerTimeParser.parseDuration("an hour") == 3_600)
        #expect(GuidedComposerTimeParser.parseDuration("1h 20m") == 4_800)
        #expect(GuidedComposerTimeParser.parseDuration("45 min") == 2_700)

        let start = date("2026-07-18T23:30:00+03:00")
        let end = date("2026-07-18T00:15:00+03:00")
        let rolled = GuidedComposerTimeParser.rolledEndIfNeeded(
            end,
            after: start,
            hadExplicitDate: false
        )
        #expect(rolled == date("2026-07-19T00:15:00+03:00"))
        #expect(
            GuidedComposerTimeParser.rolledEndIfNeeded(
                end,
                after: start,
                hadExplicitDate: true
            ) == end
        )
    }

    @Test("Reverse-order clock clauses preserve overnight semantics")
    func reverseOrderOvernightParsing() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: zone.identifier
            )
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home],
            people: [],
            transitTypes: [],
            modelContext: context
        )

        model.editorText = AttributedString(
            "Stay at Home until 00:15 from 23:30"
        )
        model.editorTextDidChange()

        #expect(model.canSubmit)
        #expect(
            model.draft.endTime?.date
                == date("2026-07-19T00:15:00+03:00")
        )

        model.editorText = AttributedString(
            "Stay at Home until today 00:15 from 23:30"
        )
        model.editorTextDidChange()

        #expect(!model.canSubmit)
        #expect(
            model.draft.endTime?.date
                == date("2026-07-18T00:15:00+03:00")
        )
    }

    @Test("Duration-derived transit boundaries use their endpoint timezone")
    func derivedBoundaryEndpointTimezone() {
        let bucharest = location(
            "Bucharest",
            latitude: 44.43,
            longitude: 26.10
        )
        let newYorkZone = TimeZone(identifier: "America/New_York")!
        let newYork = ComposerLocationCandidate(
            id: "new-york",
            displayName: "New York",
            location: Location(
                latitude: 40.71,
                longitude: -74.00,
                timeZoneIdentifier: newYorkZone.identifier
            ),
            source: .savedPlace
        )
        let start = ComposerTimeValue(
            date: date("2026-07-18T10:00:00+03:00"),
            timeZoneIdentifier: zone.identifier,
            source: .explicit
        )
        let draft = ComposerDraft(tokens: [
            token("Flight", .leading(.transit(canonicalName: "Flight"))),
            token("Bucharest", .location(bucharest, .origin)),
            token("New York", .location(newYork, .destination)),
            token("10:00", .time(start, .start)),
            token(
                "10 hr",
                .duration(
                    ComposerDurationValue(
                        interval: 10 * 60 * 60,
                        source: .manualOverride
                    )
                )
            ),
        ])

        #expect(draft.endTime?.timeZoneIdentifier == newYorkZone.identifier)
    }

    @Test("A draft requires complete distinct endpoints and time")
    func draftValidation() {
        let home = location("Home", latitude: 45.65, longitude: 25.59)
        let afi = location("AFI", latitude: 45.66, longitude: 25.61)
        let start = ComposerTimeValue(
            date: date("2026-07-18T10:00:00+03:00"),
            timeZoneIdentifier: zone.identifier,
            source: .explicit
        )
        var draft = ComposerDraft(tokens: [
            token("Bike", .leading(.transit(canonicalName: "Bicycle"))),
            token("from", .connector(.from)),
            token("Home", .location(home, .origin)),
            token("at", .connector(.at)),
            token("10:00", .time(start, .start)),
            token("to", .connector(.to)),
            token("AFI", .location(afi, .destination)),
            token(
                "20 min",
                .duration(
                    ComposerDurationValue(
                        interval: 20 * 60,
                        source: .manualOverride
                    )
                )
            ),
        ])

        #expect(draft.canSubmit)
        #expect(
            draft.endTime?.date
                == start.date.addingTimeInterval(20 * 60)
        )
        #expect(draft.durationSource == .manualOverride)

        draft.tokens.removeAll {
            if case .location(_, .destination) = $0.value { return true }
            return false
        }
        #expect(!draft.canSubmit)
    }

    @Test("Saved and MapKit duplicates retain the saved identity")
    func unifiedLocationDeduplication() throws {
        let savedID = UUID()
        let saved = ComposerLocationCandidate(
            id: "saved",
            savedPlaceID: savedID,
            displayName: "AFI Brașov",
            location: Location(
                latitude: 45.657,
                longitude: 25.601,
                formattedAddress: "Bd. 15 Noiembrie"
            ),
            source: .savedPlace
        )
        let map = ComposerLocationCandidate(
            id: "map",
            displayName: "Afi Brasov",
            location: Location(
                latitude: 45.6571,
                longitude: 25.6011,
                formattedAddress: "Bd. 15 Noiembrie"
            ),
            source: .mapKit,
            searchTerms: ["Shopping centre"]
        )

        let result = GuidedComposerLocationRanking.deduplicated([map, saved])
        #expect(result.count == 1)
        #expect(try #require(result.first).savedPlaceID == savedID)
        #expect(
            try #require(result.first).allSearchTerms.contains(
                "Shopping centre"
            )
        )
    }

    @Test("Nearby venues are not the same endpoint without matching identity")
    func nearbyDistinctLocationsRemainDistinct() {
        let cafe = Location(
            latitude: 45.6500,
            longitude: 25.5900,
            displayName: "Beach Cafe"
        )
        let shop = Location(
            latitude: 45.65005,
            longitude: 25.5900,
            displayName: "Beach Shop"
        )
        let duplicateCafe = Location(
            latitude: 45.65005,
            longitude: 25.5900,
            displayName: "Beach Cafe"
        )

        #expect(
            GuidedComposerLocationMatcher.distanceMeters(cafe, shop) < 10
        )
        #expect(!GuidedComposerLocationMatcher.sameLocation(cafe, shop))
        #expect(
            GuidedComposerLocationMatcher.sameLocation(cafe, duplicateCafe)
        )
    }

    @Test("Saved place identity survives renames and coordinate edits")
    func savedPlaceIdentityOutranksLocationPresentation() {
        let placeID = UUID()
        let oldSnapshot = ComposerLocationCandidate(
            id: "timeline-old-home",
            savedPlaceID: placeID,
            displayName: "Old Home",
            location: Location(
                latitude: 45.6500,
                longitude: 25.5900,
                displayName: "Old Home"
            ),
            source: .timeline
        )
        let currentPlace = ComposerLocationCandidate(
            id: "saved-current-home",
            savedPlaceID: placeID,
            displayName: "Home - Brașov",
            location: Location(
                latitude: 45.6502,
                longitude: 25.5902,
                displayName: "Home - Brașov"
            ),
            source: .savedPlace
        )

        #expect(
            GuidedComposerLocationMatcher.sameLocation(
                oldSnapshot,
                currentPlace
            )
        )
    }

    @Test("Token memory preserves distinct identities with the same wording")
    func tokenMemoryPreservesSameNameIdentities() {
        let first = location(
            "Platform",
            latitude: 45.6500,
            longitude: 25.5900
        )
        let second = location(
            "Platform",
            latitude: 45.6510,
            longitude: 25.5900
        )
        let memory = GuidedComposerBindingReconciler.mergedTokenMemory([
            token("Platform", .location(first, .origin)),
            token("Platform", .location(second, .origin)),
        ])

        #expect(memory.count == 2)
    }

    @Test("Replacing a value beside punctuation does not add a stray space")
    func acceptedReplacementPreservesTightPunctuation() {
        let result = GuidedComposerTextEditor.accepting(
            "Ana",
            in: "Stay with Emma, Maria",
            replacing: 10..<14
        )

        #expect(result.text == "Stay with Ana, Maria")
    }

    @Test("A ride-share alias keeps its exact match first and shows its family")
    func rideShareFamilySuggestions() throws {
        let context = try makeContext()
        let types = ["Bolt", "Uber", "Lyft", "Ride share"].map {
            TransitType(canonicalName: $0, aliases: [$0.lowercased()])
        }
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [],
            people: [],
            transitTypes: types,
            modelContext: context
        )
        #expect(model.isIdle)
        #expect(!model.shouldPresentSuggestions)
        #expect(String(model.editorText.characters).isEmpty)

        model.editorText = AttributedString("bolt")
        model.editorTextDidChange()

        #expect(!model.isIdle)
        #expect(model.shouldPresentSuggestions)
        #expect(model.suggestions.first?.title == "bolt")
        #expect(model.suggestions.contains { $0.title == "Uber" })
        #expect(model.suggestions.contains { $0.title == "Lyft" })
        #expect(model.suggestions.contains { $0.title == "Ride share" })
    }

    @Test("Space accepts an exact transit type or alias")
    func transitTypeSpaceAcceptance() throws {
        let context = try makeContext()
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [],
            people: [],
            transitTypes: [
                TransitType(canonicalName: "Bolt", aliases: ["bolt"]),
                TransitType(canonicalName: "Uber", aliases: ["uber"]),
            ],
            modelContext: context
        )

        model.editorText = AttributedString("bolt ")
        model.editorTextDidChange()

        #expect(model.draft.entryKind == .transit(canonicalName: "Bolt"))
        #expect(model.activeSlot == .connector)
        #expect(model.activeQuery.isEmpty)
    }

    @Test("The first suggestion is active and Return accepts a moved selection")
    func activeSuggestionSelection() throws {
        let context = try makeContext()
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [],
            people: [],
            transitTypes: [
                TransitType(canonicalName: "Bolt", aliases: ["bolt"]),
                TransitType(canonicalName: "Uber", aliases: ["uber"]),
            ],
            modelContext: context
        )

        model.editorText = AttributedString("bolt")
        model.editorTextDidChange()
        #expect(model.activeSuggestionID == model.suggestions.first?.id)

        let relatedUber = try #require(
            model.suggestions.first { $0.title == "Uber" }
        )
        model.activateSuggestion(relatedUber.id)
        model.activateFirstSuggestion()
        #expect(model.activeSuggestionID == model.suggestions.first?.id)

        model.activateSuggestion(relatedUber.id)
        model.editorText = AttributedString("bol")
        model.editorTextDidChange()
        #expect(model.activeSuggestionID == model.suggestions.first?.id)

        model.editorText = AttributedString("")
        model.editorTextDidChange()
        let uber = try #require(
            model.suggestions.first { $0.title == "Uber" }
        )
        model.activateSuggestion(uber.id)
        model.acceptTopSuggestion()

        #expect(model.draft.entryKind == .transit(canonicalName: "Uber"))
    }

    @Test("Only named Homes are ranked and nearby alternatives remain visible")
    func closestHomeRanking() {
        let target = location("AFI", latitude: 45.66, longitude: 25.61)
        let nearby = location(
            "Home - Brașov",
            latitude: 45.65,
            longitude: 25.60,
            systemImage: .mappin
        )
        let nearbyAlternative = location(
            "Home - Poiana",
            latitude: 45.59,
            longitude: 25.55,
            systemImage: .mappin
        )
        let distant = location(
            "Home - Constanța",
            latitude: 44.17,
            longitude: 28.63,
            systemImage: .house
        )
        let stevensPlace = location(
            "Steven’s place",
            latitude: 45.64,
            longitude: 25.58,
            systemImage: .house
        )
        let ranked = GuidedComposerLocationRanking.rankedHomeCandidates(
            [stevensPlace, distant, nearbyAlternative, nearby],
            near: target
        )

        #expect(!GuidedComposerLocationRanking.isHome(stevensPlace))
        #expect(GuidedComposerLocationRanking.isHome(nearby))
        #expect(ranked.map(\.displayName) == [
            "Home - Brașov",
            "Home - Poiana",
        ])
        #expect(
            GuidedComposerLocationRanking.rankedHomeCandidates(
                [distant],
                near: target
            ).isEmpty
        )
        #expect(
            GuidedComposerLocationRanking.contextScore(
                candidate: nearby,
                otherEndpoint: target
            ) > GuidedComposerLocationRanking.contextScore(
                candidate: distant,
                otherEndpoint: target
            )
        )
    }

    @Test("Place ranking combines fuzzy relevance with current proximity")
    func placeSuggestionProximityRanking() throws {
        let current = Location(latitude: 45.650, longitude: 25.590)
        let near = location(
            "Coffee Near",
            latitude: 45.651,
            longitude: 25.591
        )
        let far = location(
            "Coffee Far",
            latitude: 46.100,
            longitude: 26.100
        )

        let nearSearchScore = try #require(
            GuidedComposerLocationRanking.suggestionScore(
                query: "coffee",
                candidate: near,
                otherEndpoint: nil,
                currentLocation: current
            )
        )
        let farSearchScore = try #require(
            GuidedComposerLocationRanking.suggestionScore(
                query: "coffee",
                candidate: far,
                otherEndpoint: nil,
                currentLocation: current
            )
        )
        let nearEmptyScore = try #require(
            GuidedComposerLocationRanking.suggestionScore(
                query: "",
                candidate: near,
                otherEndpoint: nil,
                currentLocation: current
            )
        )
        let farEmptyScore = try #require(
            GuidedComposerLocationRanking.suggestionScore(
                query: "",
                candidate: far,
                otherEndpoint: nil,
                currentLocation: current
            )
        )
        let timeline = ComposerLocationCandidate(
            id: "timeline-coffee",
            displayName: "Coffee History",
            location: near.location,
            source: .timeline
        )

        #expect(nearSearchScore > farSearchScore)
        #expect(nearEmptyScore > farEmptyScore)
        #expect(
            GuidedComposerLocationRanking.suggestionScore(
                query: "",
                candidate: timeline,
                otherEndpoint: nil,
                currentLocation: current
            ) == nil
        )
    }

    @Test("MapKit alternatives require both absolute and relative difference")
    func mapKitAlternativeThreshold() {
        #expect(
            GuidedComposerRouteInference.shouldOfferMapKitAlternative(
                gapDuration: 30 * 60,
                routeDuration: 20 * 60
            )
        )
        #expect(
            !GuidedComposerRouteInference.shouldOfferMapKitAlternative(
                gapDuration: 30 * 60,
                routeDuration: 26 * 60
            )
        )
        #expect(
            !GuidedComposerRouteInference.shouldOfferMapKitAlternative(
                gapDuration: 60 * 60,
                routeDuration: 50 * 60
            )
        )
    }

    @Test("Timeline inference finds a missing route and suppresses an existing one")
    func routeGapAndDuplicateSuppression() {
        let homePlace = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59)
        )
        let afiPlace = Place(
            name: "AFI",
            location: Location(latitude: 45.66, longitude: 25.61)
        )
        let homeVisit = visit(
            place: homePlace,
            start: "2026-07-18T08:00:00+03:00",
            end: "2026-07-18T09:00:00+03:00"
        )
        let afiVisit = visit(
            place: afiPlace,
            start: "2026-07-18T09:30:00+03:00",
            end: "2026-07-18T10:30:00+03:00"
        )

        let missing = GuidedComposerTimelineInference.makeContext(
            entries: [afiVisit, homeVisit]
        )
        #expect(missing.gaps.count == 1)
        #expect(
            GuidedComposerTimelineInference.routeGapMacros(
                in: missing,
                timeZone: zone
            ).count == 1
        )

        let transit = LogEntry(
            kind: .transit,
            startTime: date("2026-07-18T09:00:00+03:00"),
            endTime: date("2026-07-18T09:30:00+03:00"),
            needsReview: false
        )
        transit.transitDetails = TransitDetails(
            type: "Bolt",
            originPlace: homePlace,
            destinationPlace: afiPlace
        )
        let bridged = GuidedComposerTimelineInference.makeContext(
            entries: [afiVisit, transit, homeVisit]
        )
        #expect(bridged.gaps.isEmpty)
    }

    @Test("Overnight entries only expose boundaries on the selected day")
    func overnightEntryBoundariesStayOnSelectedDay() throws {
        let beach = Place(
            name: "Beach",
            location: Location(latitude: 44.10, longitude: 28.64)
        )
        let office = Place(
            name: "Office",
            location: Location(latitude: 44.18, longitude: 28.61)
        )
        let overnight = visit(
            place: beach,
            start: "2026-07-17T19:00:00+03:00",
            end: "2026-07-18T02:00:00+03:00"
        )
        let evening = visit(
            place: office,
            start: "2026-07-18T20:00:00+03:00",
            end: "2026-07-18T21:00:00+03:00"
        )
        let context = GuidedComposerTimelineInference.makeContext(
            entries: [overnight, evening],
            selectedDay: TimelineDayKey(
                year: 2026,
                month: 7,
                day: 18
            ),
            timeZone: zone
        )

        #expect(context.gaps.count == 1)
        #expect(
            context.gaps.first?.startTime
                == date("2026-07-18T02:00:00+03:00")
        )
        #expect(
            context.gaps.first?.endTime
                == date("2026-07-18T20:00:00+03:00")
        )
        #expect(
            !GuidedComposerTimelineInference
                .shouldOfferLeadingHomeRoute(in: context)
        )

        let newOrigin = location(
            "New origin",
            latitude: 44.15,
            longitude: 28.60
        )
        let requests = GuidedComposerRouteInference.anchoredRouteRequests(
            in: context,
            selectedOrigin: newOrigin,
            selectedDestination: nil
        )
        #expect(requests.count == 1)
        guard case .arrival(let arrival) = try #require(requests.first).anchor
        else {
            Issue.record("Expected an arrival boundary")
            return
        }
        #expect(arrival == date("2026-07-18T20:00:00+03:00"))
    }

    @Test("Picker defaults to the current clock on the selected day")
    func pickerDefaultsToCurrentClock() throws {
        let context = try makeContext()
        let model = GuidedEntryComposerModel()
        let fixedNow = date("2026-08-04T15:23:00+03:00")
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [],
            people: [],
            transitTypes: [],
            modelContext: context
        )

        let pickerDate = model.suggestedPickerDate(
            for: .start,
            now: fixedNow
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: pickerDate
        )
        #expect(components.year == 2026)
        #expect(components.month == 7)
        #expect(components.day == 18)
        #expect(components.hour == 15)
        #expect(components.minute == 23)
    }

    @Test("Now remains available alongside end-time presets")
    func nowRemainsAnEndTimeSuggestion() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(
                latitude: 44.18,
                longitude: 28.61,
                timeZoneIdentifier: zone.identifier
            )
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: .today(timeZone: zone),
            places: [home],
            people: [],
            transitTypes: [],
            modelContext: context
        )
        model.editorText = AttributedString(
            "Stay at Home from 10:00 to "
        )
        model.editorTextDidChange()

        #expect(model.activeSlot == .time(.end))
        #expect(model.suggestions.contains { suggestion in
            suggestion.id == "time-now-end"
        })
        #expect(model.suggestions.contains { suggestion in
            suggestion.subtitle?.contains("minutes after departure")
                == true
        })
    }

    @Test("Wheel times use minute precision and roll overnight ends")
    func wheelTimeNormalizesAndRollsOvernight() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(
                latitude: 44.18,
                longitude: 28.61,
                timeZoneIdentifier: zone.identifier
            )
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home],
            people: [],
            transitTypes: [],
            modelContext: context
        )
        model.editorText = AttributedString(
            "Stay at Home from 23:00 to "
        )
        model.editorTextDidChange()

        model.selectTime(
            date("2026-07-18T02:15:47+03:00"),
            role: .end
        )

        #expect(
            model.draft.time(.end)?.date
                == date("2026-07-19T02:15:00+03:00")
        )
        #expect(model.canSubmit)
    }

    @Test("Partial routes project their destination and timeline times")
    func partialRouteProjectsDestinationAndTimes() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: zone.identifier
            )
        )
        let reyna = Place(
            name: "Reyna Beach",
            location: Location(
                latitude: 44.10,
                longitude: 28.64,
                timeZoneIdentifier: zone.identifier
            )
        )
        context.insert(home)
        context.insert(reyna)
        context.insert(
            visit(
                place: home,
                start: "2026-07-18T10:00:00+03:00",
                end: "2026-07-18T11:00:00+03:00"
            )
        )
        context.insert(
            visit(
                place: reyna,
                start: "2026-07-18T12:00:00+03:00",
                end: "2026-07-18T13:00:00+03:00"
            )
        )
        try context.save()

        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home, reyna],
            people: [],
            transitTypes: [
                TransitType(canonicalName: "Bolt", aliases: ["bolt"]),
            ],
            modelContext: context
        )
        model.editorText = AttributedString("Bolt from ")
        model.editorTextDidChange()

        let originSuggestion = try #require(model.suggestions.first)
        guard case .macro(let originTokens, _) = originSuggestion.kind else {
            Issue.record("Expected a smart origin macro")
            return
        }
        #expect(routeRoles(in: originTokens) == Set([
            .location(.origin),
            .location(.destination),
            .time(.start),
            .time(.end),
        ]))

        model.editorText = AttributedString("Bolt from Home to ")
        model.editorTextDidChange()

        let destinationSuggestion = try #require(
            model.suggestions.first
        )
        guard case .macro(let destinationTokens, _) =
            destinationSuggestion.kind else {
            Issue.record("Expected a smart destination macro")
            return
        }
        #expect(destinationTokens.contains {
            if case .location(let value, .destination) = $0.value {
                return value.displayName == "Reyna Beach"
            }
            return false
        })
        #expect(destinationTokens.contains {
            if case .time(_, .start) = $0.value { return true }
            return false
        })
        #expect(destinationTokens.contains {
            if case .time(_, .end) = $0.value { return true }
            return false
        })

        model.accept(destinationSuggestion)
        #expect(model.draft.location(.destination)?.displayName == "Reyna Beach")
        #expect(model.draft.time(.start)?.date ==
            date("2026-07-18T11:00:00+03:00"))
        #expect(model.draft.time(.end)?.date ==
            date("2026-07-18T12:00:00+03:00"))
        #expect(model.canSubmit)
    }

    @Test("Any selected endpoint produces timeline-anchored route requests")
    func arbitraryEndpointCreatesAnchoredRequests() throws {
        let reynaPlace = Place(
            name: "Reyna Beach",
            location: Location(latitude: 44.10, longitude: 28.64)
        )
        let reynaVisit = visit(
            place: reynaPlace,
            start: "2026-07-18T12:00:00+03:00",
            end: "2026-07-18T13:00:00+03:00"
        )
        let context = GuidedComposerTimelineInference.makeContext(
            entries: [reynaVisit]
        )
        let office = location(
            "Office",
            latitude: 44.15,
            longitude: 28.60
        )
        let reyna = try #require(context.intervals.first?.startLocation)

        let arriving = GuidedComposerRouteInference
            .anchoredRouteRequests(
                in: context,
                selectedOrigin: office,
                selectedDestination: nil
            )
        let departing = GuidedComposerRouteInference
            .anchoredRouteRequests(
                in: context,
                selectedOrigin: nil,
                selectedDestination: office
            )

        #expect(arriving.count == 1)
        #expect(
            GuidedComposerLocationMatcher.sameLocation(
                arriving[0].destination.location,
                reyna.location
            )
        )
        #expect(
            arriving[0].interval(for: 30 * 60).end
                == date("2026-07-18T12:00:00+03:00")
        )
        #expect(departing.count == 1)
        #expect(
            GuidedComposerLocationMatcher.sameLocation(
                departing[0].origin.location,
                reyna.location
            )
        )
        #expect(
            departing[0].interval(for: 30 * 60).start
                == date("2026-07-18T13:00:00+03:00")
        )
    }

    @Test("Known timeline endpoints only use their adjacent gaps")
    func knownEndpointUsesOnlyAdjacentGaps() throws {
        let workoutOrigin = Location(
            latitude: 45.70,
            longitude: 25.60,
            displayName: "Trailhead",
            timeZoneIdentifier: zone.identifier
        )
        let workoutDestination = Location(
            latitude: 45.71,
            longitude: 25.61,
            displayName: "Summit",
            timeZoneIdentifier: zone.identifier
        )
        let workout = LogEntry(
            kind: .workout,
            startTime: date("2026-07-18T09:00:00+03:00"),
            endTime: date("2026-07-18T10:00:00+03:00"),
            needsReview: false
        )
        workout.workoutDetails = WorkoutDetails(
            healthKitWorkoutUUID: UUID(),
            activityTypeRawValue: 52,
            activityName: "Walk",
            movementKind: .moving,
            originLocation: workoutOrigin,
            destinationLocation: workoutDestination
        )
        let beachPlace = Place(
            name: "Beach",
            location: Location(
                latitude: 44.10,
                longitude: 28.64,
                timeZoneIdentifier: zone.identifier
            )
        )
        let beachVisit = visit(
            place: beachPlace,
            start: "2026-07-18T12:00:00+03:00",
            end: "2026-07-18T13:00:00+03:00"
        )
        let context = GuidedComposerTimelineInference.makeContext(
            entries: [workout, beachVisit]
        )
        let beach = try #require(context.intervals.last?.endLocation)
        let trailhead = try #require(
            context.intervals.first?.startLocation
        )

        let beachRequests = GuidedComposerRouteInference
            .anchoredRouteRequests(
            in: context,
            selectedOrigin: beach,
            selectedDestination: nil
        )
        let trailheadRequests = GuidedComposerRouteInference
            .anchoredRouteRequests(
                in: context,
                selectedOrigin: trailhead,
                selectedDestination: nil
            )

        #expect(context.gaps.count == 1)
        #expect(beachRequests.isEmpty)
        #expect(trailheadRequests.isEmpty)
    }

    @Test("A route can reuse a free departure boundary with a new destination")
    func routeReusesFreeOriginBoundary() throws {
        let originPlace = Place(
            name: "Place A",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: zone.identifier
            )
        )
        let nextPlace = Place(
            name: "Place B",
            location: Location(
                latitude: 45.70,
                longitude: 25.65,
                timeZoneIdentifier: zone.identifier
            )
        )
        let first = visit(
            place: originPlace,
            start: "2026-07-18T09:00:00+03:00",
            end: "2026-07-18T10:00:00+03:00"
        )
        let second = visit(
            place: nextPlace,
            start: "2026-07-18T12:00:00+03:00",
            end: "2026-07-18T13:00:00+03:00"
        )
        let context = GuidedComposerTimelineInference.makeContext(
            entries: [first, second]
        )
        let selectedOrigin = try #require(
            context.intervals.first?.endLocation
        )

        let suggestions = GuidedComposerTimelineInference.boundaryTimes(
            for: .start,
            location: selectedOrigin,
            in: context
        )

        #expect(suggestions.count == 1)
        #expect(
            suggestions.first?.date
                == date("2026-07-18T10:00:00+03:00")
        )
        #expect(suggestions.first?.timeZoneIdentifier == zone.identifier)
    }

    @Test("New endpoints can project into every available boundary")
    func newEndpointUsesAllAvailableBoundaries() {
        let firstPlace = Place(
            name: "Trailhead",
            location: Location(latitude: 45.70, longitude: 25.60)
        )
        let secondPlace = Place(
            name: "Beach",
            location: Location(latitude: 44.10, longitude: 28.64)
        )
        let first = visit(
            place: firstPlace,
            start: "2026-07-18T09:00:00+03:00",
            end: "2026-07-18T10:00:00+03:00"
        )
        let second = visit(
            place: secondPlace,
            start: "2026-07-18T12:00:00+03:00",
            end: "2026-07-18T13:00:00+03:00"
        )
        let context = GuidedComposerTimelineInference.makeContext(
            entries: [first, second]
        )
        let newOrigin = location(
            "New Beach",
            latitude: 43.95,
            longitude: 28.63
        )

        let requests = GuidedComposerRouteInference.anchoredRouteRequests(
            in: context,
            selectedOrigin: newOrigin,
            selectedDestination: nil
        )

        #expect(requests.count == 2)
        #expect(Set(requests.map(\.destination.displayName)) == Set([
            "Trailhead",
            "Beach",
        ]))
    }

    @Test("Committed route times reject unrelated timeline projections")
    func committedTimesConstrainRouteProjection() {
        let home = location(
            "Home",
            latitude: 45.65,
            longitude: 25.59
        )
        let beach = location(
            "Beach",
            latitude: 44.10,
            longitude: 28.64
        )
        let route = GuidedComposerRouteInference.routeSuggestion(
            id: "morning-route",
            origin: home,
            destination: beach,
            start: date("2026-07-18T09:00:00+03:00"),
            end: date("2026-07-18T10:00:00+03:00"),
            timeSource: .history,
            durationSource: .mapkitCarFallback,
            subtitle: "Morning gap",
            score: 10_000
        )
        let incompatibleStart = ComposerTokenFactory.explicitTime(
            date: date("2026-07-18T12:00:00+03:00"),
            timeZone: zone,
            role: .start,
            displayText: "12:00",
            allowsOvernightRollover: false
        )
        let draft = ComposerDraft(tokens: [
            token(
                "Bolt",
                .leading(.transit(canonicalName: "Bolt"))
            ),
            token("from", .connector(.from)),
            token("Home", .location(home, .origin)),
            incompatibleStart,
        ])

        #expect(
            GuidedComposerRouteInference.projectedSuggestions(
                from: [route],
                draft: draft,
                activeSlot: .connector,
                query: ""
            ).isEmpty
        )
    }

    @Test("Empty place slots hide unrelated timeline endpoints")
    func emptyPlaceQuerySuppressesUnrelatedHistory() throws {
        let modelContext = try makeContext()
        let beach = Place(
            name: "Beach",
            location: Location(latitude: 44.10, longitude: 28.64)
        )
        let home = Place(
            name: "Home",
            location: Location(latitude: 44.11, longitude: 28.65),
            systemImage: .house
        )
        let workout = LogEntry(
            kind: .workout,
            startTime: date("2026-07-18T09:00:00+03:00"),
            endTime: date("2026-07-18T10:00:00+03:00"),
            needsReview: false
        )
        workout.workoutDetails = WorkoutDetails(
            healthKitWorkoutUUID: UUID(),
            activityTypeRawValue: 52,
            activityName: "Walk",
            movementKind: .moving,
            originLocation: Location(
                latitude: 45.70,
                longitude: 25.60,
                displayName: "Trailhead"
            ),
            destinationLocation: Location(
                latitude: 45.71,
                longitude: 25.61,
                displayName: "Summit"
            )
        )
        let beachVisit = visit(
            place: beach,
            start: "2026-07-18T12:00:00+03:00",
            end: "2026-07-18T13:00:00+03:00"
        )
        modelContext.insert(beach)
        modelContext.insert(home)
        modelContext.insert(workout)
        modelContext.insert(beachVisit)
        try modelContext.save()

        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [beach, home],
            people: [],
            transitTypes: [
                TransitType(canonicalName: "Bolt", aliases: ["bolt"]),
            ],
            modelContext: modelContext
        )
        model.editorText = AttributedString("Bolt from Beach to ")
        model.editorTextDidChange()

        #expect(model.suggestions.contains { $0.title == "Home" })
        #expect(!model.suggestions.contains {
            $0.title.contains("Trailhead") || $0.title.contains("Summit")
        })

        model.editorText = AttributedString("Bolt from Beach to trail")
        model.editorTextDidChange()
        #expect(model.suggestions.contains { $0.title == "Trailhead" })
    }

    @Test("Smart routes remain complete through every transit phase")
    func smartRouteProjectionPhaseMatrix() throws {
        let home = location(
            "Home",
            latitude: 45.65,
            longitude: 25.59
        )
        let beach = location(
            "Beach",
            latitude: 44.10,
            longitude: 28.64
        )
        let start = date("2026-07-18T19:25:00+03:00")
        let end = date("2026-07-18T19:40:00+03:00")
        let route = GuidedComposerRouteInference.routeSuggestion(
            id: "phase-route",
            origin: home,
            destination: beach,
            start: start,
            end: end,
            timeSource: .history,
            durationSource: .mapkitCarFallback,
            subtitle: "Timeline route",
            score: 10_000
        )
        let leading = token(
            "Bolt",
            .leading(.transit(canonicalName: "Bolt"))
        )
        let from = token("from", .connector(.from))
        let to = token("to", .connector(.to))
        let origin = token("Home", .location(home, .origin))
        let destination = token(
            "Beach",
            .location(beach, .destination)
        )
        let startToken = token(
            "19:25",
            .time(
                ComposerTimeValue(
                    date: start,
                    timeZoneIdentifier: zone.identifier,
                    source: .explicit
                ),
                .start
            )
        )

        func projected(
            _ tokens: [ComposerToken],
            slot: ComposerSlot
        ) throws -> [ComposerToken] {
            let suggestions = GuidedComposerRouteInference
                .projectedSuggestions(
                    from: [route],
                    draft: ComposerDraft(tokens: tokens),
                    activeSlot: slot,
                    query: ""
                )
            guard let suggestion = suggestions.first,
                  case .macro(let values, _) = suggestion.kind else {
                Issue.record("Expected a smart route macro for \(slot)")
                return []
            }
            return values
        }

        let afterType = try projected([leading], slot: .connector)
        #expect(routeRoles(in: afterType) == Set([
            .location(.origin),
            .location(.destination),
            .time(.start),
            .time(.end),
        ]))

        let afterFrom = try projected(
            [leading, from],
            slot: .location(.origin)
        )
        #expect(routeRoles(in: afterFrom) == Set([
            .location(.origin),
            .location(.destination),
            .time(.start),
            .time(.end),
        ]))

        let afterTo = try projected(
            [leading, to],
            slot: .location(.destination)
        )
        #expect(routeRoles(in: afterTo) == Set([
            .location(.origin),
            .location(.destination),
            .time(.start),
            .time(.end),
        ]))

        let afterOrigin = try projected(
            [leading, from, origin],
            slot: .connector
        )
        #expect(routeRoles(in: afterOrigin) == Set([
            .location(.destination),
            .time(.start),
            .time(.end),
        ]))

        let afterEndpoints = try projected(
            [leading, from, origin, to, destination],
            slot: .connector
        )
        #expect(routeRoles(in: afterEndpoints) == Set([
            .time(.start),
            .time(.end),
        ]))

        let originAdjacentTime = try projected(
            [
                leading,
                from,
                origin,
                token("at", .connector(.at)),
            ],
            slot: .time(.start)
        )
        #expect(routeRoles(in: originAdjacentTime) == Set([
            .location(.destination),
            .time(.start),
            .time(.end),
        ]))
        #expect(originAdjacentTime.contains {
            $0.role == .location(.destination)
        })

        let destinationAdjacentTime = try projected(
            [
                leading,
                to,
                destination,
                token("at", .connector(.at)),
            ],
            slot: .time(.end)
        )
        #expect(routeRoles(in: destinationAdjacentTime) == Set([
            .location(.origin),
            .time(.start),
            .time(.end),
        ]))
        #expect(destinationAdjacentTime.contains {
            $0.role == .location(.origin)
        })

        let afterStart = GuidedComposerRouteInference
            .projectedSuggestions(
                from: [route],
                draft: ComposerDraft(tokens: [
                    leading,
                    from,
                    origin,
                    to,
                    destination,
                    startToken,
                ]),
                activeSlot: .connector,
                query: ""
            )
        #expect(afterStart.isEmpty)
    }

    @Test("MapKit derives only the missing transit boundary")
    func mapKitBoundaryDerivation() {
        let start = date("2026-07-18T19:25:00+03:00")
        let end = date("2026-07-18T19:40:00+03:00")

        #expect(
            GuidedComposerRouteInference.derivedBoundaryTime(
                role: .end,
                start: start,
                end: nil,
                duration: 15 * 60
            ) == end
        )
        #expect(
            GuidedComposerRouteInference.derivedBoundaryTime(
                role: .start,
                start: nil,
                end: end,
                duration: 15 * 60
            ) == start
        )
        #expect(
            GuidedComposerRouteInference.derivedBoundaryTime(
                role: .end,
                start: nil,
                end: nil,
                duration: 15 * 60
            ) == nil
        )
    }

    @Test("Timeline suggestions only use the selected day")
    func selectedDayTimelineFiltering() {
        let place = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59)
        )
        let selectedVisit = visit(
            place: place,
            start: "2026-07-18T08:00:00+03:00",
            end: "2026-07-18T09:00:00+03:00"
        )
        let olderVisit = visit(
            place: place,
            start: "2026-07-16T08:00:00+03:00",
            end: "2026-07-16T09:00:00+03:00"
        )

        let context = GuidedComposerTimelineInference.makeContext(
            entries: [olderVisit, selectedVisit],
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18)
        )

        #expect(context.intervals.map(\.id) == [selectedVisit.id])
        #expect(
            context.endpointCandidates.allSatisfy {
                $0.id.contains(selectedVisit.id.uuidString)
            }
        )
    }

    @Test("Reviewed workouts do not consume searchable ordinals")
    func reviewedWorkoutsDoNotConsumeOrdinals() {
        let origin = Location(
            latitude: 45.65,
            longitude: 25.60,
            displayName: "Trail start",
            timeZoneIdentifier: zone.identifier
        )
        let destination = Location(
            latitude: 45.66,
            longitude: 25.61,
            displayName: "Trail end",
            timeZoneIdentifier: zone.identifier
        )
        let reviewed = LogEntry(
            kind: .workout,
            startTime: date("2026-07-27T06:00:00Z"),
            endTime: date("2026-07-27T06:30:00Z"),
            needsReview: false
        )
        reviewed.workoutDetails = WorkoutDetails(
            healthKitWorkoutUUID: UUID(),
            activityTypeRawValue: 52,
            activityName: "Walk",
            movementKind: .moving,
            originLocation: origin,
            destinationLocation: destination,
            fieldReviews: [
                WorkoutFieldReview(
                    field: .origin,
                    reason: "Needs confirmation"
                ),
            ]
        )
        let inferable = LogEntry(
            kind: .workout,
            startTime: date("2026-07-27T07:00:00Z"),
            endTime: date("2026-07-27T07:30:00Z"),
            needsReview: false
        )
        inferable.workoutDetails = WorkoutDetails(
            healthKitWorkoutUUID: UUID(),
            activityTypeRawValue: 52,
            activityName: "Walk",
            movementKind: .moving,
            originLocation: origin,
            destinationLocation: destination
        )

        let context = GuidedComposerTimelineInference.makeContext(
            entries: [reviewed, inferable]
        )

        #expect(context.intervals.map(\.label) == ["first Walk"])
        let searchTerms = context.endpointCandidates.flatMap(\.searchTerms)
        #expect(searchTerms.contains("first Walk origin"))
        #expect(searchTerms.contains("last Walk origin"))
        #expect(!searchTerms.contains("second Walk origin"))
    }

    @Test("Preparing after a SwiftData deletion drops stale route gaps")
    func timelineRefreshDropsDeletedEntries() throws {
        let context = try makeContext()
        let beach = Place(
            name: "Beach",
            location: Location(latitude: 44.10, longitude: 28.64)
        )
        let home = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59)
        )
        let beachVisit = visit(
            place: beach,
            start: "2026-07-18T12:00:00+03:00",
            end: "2026-07-18T13:00:00+03:00"
        )
        let homeVisit = visit(
            place: home,
            start: "2026-07-18T14:00:00+03:00",
            end: "2026-07-18T15:00:00+03:00"
        )
        context.insert(beach)
        context.insert(home)
        context.insert(beachVisit)
        context.insert(homeVisit)
        try context.save()

        let selectedDay = TimelineDayKey(
            year: 2026,
            month: 7,
            day: 18
        )
        let transitTypes = [
            TransitType(canonicalName: "Bolt", aliases: ["bolt"]),
        ]
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: selectedDay,
            places: [beach, home],
            people: [],
            transitTypes: transitTypes,
            modelContext: context
        )
        model.editorText = AttributedString("Bolt ")
        model.editorTextDidChange()
        #expect(model.suggestions.contains {
            $0.id.contains("route-gap-")
        })

        context.delete(homeVisit)
        try context.save()
        model.prepare(
            selectedDay: selectedDay,
            places: [beach, home],
            people: [],
            transitTypes: transitTypes,
            modelContext: context
        )

        #expect(!model.suggestions.contains {
            $0.id.contains("route-gap-")
        })
    }

    @Test("Overlapping entries use the latest known boundary for gaps")
    func overlappingTimelineGapFrontier() throws {
        let home = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59)
        )
        let beach = Place(
            name: "Beach",
            location: Location(latitude: 45.66, longitude: 25.60)
        )
        let office = Place(
            name: "Office",
            location: Location(latitude: 45.67, longitude: 25.61)
        )
        let longVisit = visit(
            place: home,
            start: "2026-07-18T10:00:00+03:00",
            end: "2026-07-18T14:00:00+03:00"
        )
        let nestedVisit = visit(
            place: beach,
            start: "2026-07-18T11:00:00+03:00",
            end: "2026-07-18T12:00:00+03:00"
        )
        let followingVisit = visit(
            place: office,
            start: "2026-07-18T15:00:00+03:00",
            end: "2026-07-18T16:00:00+03:00"
        )

        let timeline = GuidedComposerTimelineInference.makeContext(
            entries: [nestedVisit, followingVisit, longVisit],
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18)
        )

        let gap = try #require(timeline.gaps.first)
        #expect(timeline.gaps.count == 1)
        #expect(gap.previous.id == longVisit.id)
        #expect(gap.next.id == followingVisit.id)
        #expect(gap.startTime == date("2026-07-18T14:00:00+03:00"))
        #expect(
            !GuidedComposerTimelineInference.hasInferenceWindow(
                before: 1,
                in: timeline
            )
        )
        #expect(
            !GuidedComposerTimelineInference.hasInferenceWindow(
                after: 1,
                in: timeline
            )
        )
        #expect(
            GuidedComposerTimelineInference.hasInferenceWindow(
                before: 2,
                in: timeline
            )
        )
    }

    @Test("Removed semantic identities no longer remain resolved")
    func removedPersonInvalidatesComposerBinding() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: zone.identifier
            )
        )
        let emma = Person(name: "Emma")
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home],
            people: [emma],
            transitTypes: [],
            modelContext: context
        )
        model.editorText = AttributedString(
            "Stay at Home from 12:00 to 13:00 with Emma"
        )
        model.editorTextDidChange()
        #expect(model.canSubmit)
        #expect(model.draft.people.map(\.id) == [emma.id])

        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home],
            people: [],
            transitTypes: [],
            modelContext: context
        )

        #expect(!model.canSubmit)
        #expect(model.draft.people.isEmpty)
        #expect(model.activeSlot == .person)
    }

    @Test("Committed saved places refresh their canonical location")
    func savedPlaceBindingRefreshesCanonicalValue() throws {
        let placeID = UUID()
        let oldCandidate = ComposerLocationCandidate(
            id: "saved-old",
            savedPlaceID: placeID,
            displayName: "Home",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                displayName: "Home"
            ),
            source: .savedPlace
        )
        let updatedCandidate = ComposerLocationCandidate(
            id: "saved-updated",
            savedPlaceID: placeID,
            displayName: "Home",
            location: Location(
                latitude: 44.10,
                longitude: 28.64,
                displayName: "Home"
            ),
            source: .savedPlace
        )
        let text = "Stay at Home from 12:00 to 13:00"
        let snapshot = GuidedComposerSemanticParser.parse(
            GuidedComposerSemanticParser.Input(
                text: text,
                selection: text.count..<text.count,
                bindings: [
                    ComposerSemanticBinding(
                        token: token(
                            "Home",
                            .location(oldCandidate, .visit)
                        ),
                        range: 8..<12
                    ),
                ],
                transitTypes: [],
                locations: [updatedCandidate],
                people: [],
                selectedDay: TimelineDayKey(
                    year: 2026,
                    month: 7,
                    day: 18
                )
            )
        )
        let location = try #require(
            ComposerDraft(tokens: snapshot.tokens).location(.visit)
        )

        #expect(snapshot.isSyntaxValid)
        #expect(location.id == updatedCandidate.id)
        #expect(location.location == updatedCandidate.location)
    }

    @Test("Every internal gap is suggested regardless of entry kind")
    func everyTimelineGapIsSuggested() {
        let places = (0..<6).map { index in
            Place(
                name: "Place \(index)",
                location: Location(
                    latitude: 45.60 + Double(index) * 0.01,
                    longitude: 25.50 + Double(index) * 0.01
                )
            )
        }
        let entries = places.enumerated().map { index, place in
            visit(
                place: place,
                start: String(
                    format: "2026-07-18T%02d:00:00+03:00",
                    8 + index * 2
                ),
                end: String(
                    format: "2026-07-18T%02d:30:00+03:00",
                    8 + index * 2
                )
            )
        }
        let context = GuidedComposerTimelineInference.makeContext(
            entries: entries
        )

        #expect(context.gaps.count == 5)
        #expect(
            GuidedComposerTimelineInference.routeGapMacros(
                in: context,
                timeZone: zone
            ).count == 5
        )
        #expect(
            GuidedComposerTimelineInference
                .shouldOfferLeadingHomeRoute(in: context)
        )
        #expect(
            GuidedComposerTimelineInference
                .shouldOfferTrailingHomeRoute(in: context)
        )
    }

    @Test("Inference requires at least a five-minute internal gap")
    func minimumInferenceGap() {
        let home = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59)
        )
        let beach = Place(
            name: "Beach",
            location: Location(latitude: 44.10, longitude: 28.64)
        )
        let previous = visit(
            place: home,
            start: "2026-07-18T08:00:00+03:00",
            end: "2026-07-18T09:00:00+03:00"
        )
        let fourMinutesLater = visit(
            place: beach,
            start: "2026-07-18T09:04:00+03:00",
            end: "2026-07-18T10:00:00+03:00"
        )
        let fiveMinutesLater = visit(
            place: beach,
            start: "2026-07-18T09:05:00+03:00",
            end: "2026-07-18T10:00:00+03:00"
        )

        let shortContext = GuidedComposerTimelineInference.makeContext(
            entries: [previous, fourMinutesLater]
        )
        let eligibleContext = GuidedComposerTimelineInference.makeContext(
            entries: [previous, fiveMinutesLater]
        )

        #expect(shortContext.gaps.isEmpty)
        #expect(
            !GuidedComposerTimelineInference.hasInferenceWindow(
                before: 1,
                in: shortContext
            )
        )
        #expect(eligibleContext.gaps.count == 1)
        #expect(
            GuidedComposerTimelineInference.hasInferenceWindow(
                before: 1,
                in: eligibleContext
            )
        )
    }

    @Test("Adjacent entries produce no route or visit suggestions")
    func adjacentEntriesSuppressInference() {
        let home = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59)
        )
        let beach = Place(
            name: "Beach",
            location: Location(latitude: 44.10, longitude: 28.64)
        )
        let outbound = transit(
            origin: home,
            destination: beach,
            start: "2026-07-18T10:00:00+03:00",
            end: "2026-07-18T10:30:00+03:00"
        )
        let homeVisit = visit(
            place: home,
            start: "2026-07-18T10:30:00+03:00",
            end: "2026-07-18T11:00:00+03:00"
        )
        let inbound = transit(
            origin: beach,
            destination: home,
            start: "2026-07-18T11:00:00+03:00",
            end: "2026-07-18T11:30:00+03:00"
        )
        let context = GuidedComposerTimelineInference.makeContext(
            entries: [outbound, homeVisit, inbound]
        )
        let homeCandidate = location(
            "Home",
            latitude: 45.65,
            longitude: 25.59
        )

        #expect(context.gaps.isEmpty)
        #expect(
            GuidedComposerTimelineInference.routeGapMacros(
                in: context,
                timeZone: zone
            ).isEmpty
        )
        #expect(
            GuidedComposerRouteInference.anchoredRouteRequests(
                in: context,
                selectedOrigin: homeCandidate,
                selectedDestination: nil
            ).isEmpty
        )
        #expect(
            GuidedComposerRouteInference.anchoredRouteRequests(
                in: context,
                selectedOrigin: nil,
                selectedDestination: homeCandidate
            ).isEmpty
        )
        #expect(
            GuidedComposerTimelineInference.visitMacros(
                in: context,
                timeZone: zone
            ).isEmpty
        )
    }

    @Test("Home-ended boundary transits suppress redundant edge routes")
    func homeBoundaryTransitSuppression() {
        let home = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59),
            systemImage: .house
        )
        let afi = Place(
            name: "AFI",
            location: Location(latitude: 45.66, longitude: 25.61)
        )
        let cinema = Place(
            name: "Cinema",
            location: Location(latitude: 45.67, longitude: 25.63)
        )
        let first = transit(
            origin: home,
            destination: afi,
            start: "2026-07-18T08:00:00+03:00",
            end: "2026-07-18T08:30:00+03:00"
        )
        let last = transit(
            origin: cinema,
            destination: home,
            start: "2026-07-18T10:00:00+03:00",
            end: "2026-07-18T10:30:00+03:00"
        )
        let context = GuidedComposerTimelineInference.makeContext(
            entries: [last, first]
        )

        #expect(context.gaps.count == 1)
        #expect(context.gaps.first?.previous.kind == .transit)
        #expect(context.gaps.first?.next.kind == .transit)
        #expect(
            !GuidedComposerTimelineInference
                .shouldOfferLeadingHomeRoute(in: context)
        )
        #expect(
            !GuidedComposerTimelineInference
                .shouldOfferTrailingHomeRoute(in: context)
        )
    }

    @Test("Visit inference never creates a zero-length interval")
    func visitInferenceRejectsEqualBoundaries() throws {
        let home = Place(
            name: "Home",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: zone.identifier
            )
        )
        let afi = Place(
            name: "AFI",
            location: Location(
                latitude: 45.66,
                longitude: 25.61,
                timeZoneIdentifier: zone.identifier
            )
        )
        let transit = LogEntry(
            kind: .transit,
            startTime: date("2026-07-18T09:30:00+03:00"),
            endTime: date("2026-07-18T10:00:00+03:00"),
            needsReview: false
        )
        transit.transitDetails = TransitDetails(
            type: "Car",
            originPlace: afi,
            destinationPlace: home
        )
        let visit = self.visit(
            place: home,
            start: "2026-07-18T10:00:00+03:00",
            end: "2026-07-18T11:00:00+03:00"
        )
        let context = GuidedComposerTimelineInference.makeContext(
            entries: [transit, visit]
        )
        let macros = GuidedComposerTimelineInference.visitMacros(
            in: context,
            timeZone: zone
        )
        #expect(!macros.isEmpty)
        for macro in macros {
            guard case .macro(let tokens, _) = macro.kind else {
                Issue.record("Expected visit macro")
                continue
            }
            let start = tokens.compactMap {
                if case .time(let value, .start) = $0.value {
                    return value.date
                }
                return nil
            }.first
            let end = tokens.compactMap {
                if case .time(let value, .end) = $0.value {
                    return value.date
                }
                return nil
            }.first
            if let start, let end {
                #expect(end > start)
            }
        }
    }

    @Test("Dangling transit endpoints become partial visit suggestions")
    func danglingTransitCreatesVisitSuggestions() throws {
        let afi = Place(
            name: "AFI",
            location: Location(
                latitude: 45.66,
                longitude: 25.61,
                timeZoneIdentifier: zone.identifier
            )
        )
        let reyna = Place(
            name: "Reyna Beach",
            location: Location(
                latitude: 44.10,
                longitude: 28.64,
                timeZoneIdentifier: zone.identifier
            )
        )
        let route = transit(
            origin: afi,
            destination: reyna,
            start: "2026-07-18T11:00:00+03:00",
            end: "2026-07-18T11:30:00+03:00"
        )
        let context = GuidedComposerTimelineInference.makeContext(
            entries: [route]
        )
        let macros = GuidedComposerTimelineInference.visitMacros(
            in: context,
            timeZone: zone
        )

        #expect(macros.contains { $0.id.hasPrefix("visit-before-") })
        #expect(macros.contains { $0.id.hasPrefix("visit-after-") })

        let reynaCandidate = try #require(
            context.intervals.first?.endLocation
        )
        let draft = ComposerDraft(tokens: [
            token("Stay", .leading(.placeVisit(description: nil))),
            token("at", .connector(.at)),
            token(
                "Reyna Beach",
                .location(reynaCandidate, .visit)
            ),
        ])
        let projected = GuidedComposerTimelineInference
            .projectedVisitSuggestions(
                from: macros,
                draft: draft,
                activeSlot: .connector,
                query: ""
            )
        let afterTransit = try #require(
            projected.first { $0.id.hasPrefix("visit-after-") }
        )
        guard case .macro(let tokens, _) = afterTransit.kind else {
            Issue.record("Expected a projected visit macro")
            return
        }
        #expect(tokens.contains {
            if case .time(let value, .start) = $0.value {
                return value.date
                    == date("2026-07-18T11:30:00+03:00")
            }
            return false
        })

        let existingVisit = visit(
            place: reyna,
            start: "2026-07-18T11:30:00+03:00",
            end: "2026-07-18T12:30:00+03:00"
        )
        let coveredContext = GuidedComposerTimelineInference.makeContext(
            entries: [route, existingVisit]
        )
        #expect(
            !GuidedComposerTimelineInference.visitMacros(
                in: coveredContext,
                timeZone: zone
            ).contains {
                $0.id == "visit-after-\(route.id.uuidString)"
            }
        )
    }

    @Test("Freeform connector edits reparse without rewriting the input")
    func freeformConnectorEditing() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59)
        )
        let afi = Place(
            name: "AFI",
            location: Location(latitude: 45.66, longitude: 25.61)
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home, afi],
            people: [],
            transitTypes: [
                TransitType(canonicalName: "Bolt", aliases: ["bolt"]),
            ],
            modelContext: context
        )

        let valid = "Bolt from Home at 6:00 to AFI at 6:30"
        model.editorText = AttributedString(valid)
        model.editorTextDidChange()
        #expect(model.isSyntaxValid)
        #expect(model.canSubmit)

        let missingConnector = "Bolt Home at 6:00 to AFI at 6:30"
        model.editorText = AttributedString(missingConnector)
        model.editorTextDidChange()
        #expect(!model.isSyntaxValid)
        #expect(!model.canSubmit)
        #expect(String(model.editorText.characters) == missingConnector)

        let changedConnector = "Bolt to Home at 6:00 to AFI at 6:30"
        model.editorText = AttributedString(changedConnector)
        model.editorTextDidChange()
        #expect(model.draft.tokens.contains {
            if case .location(let candidate, .destination) = $0.value {
                return candidate.displayName == "Home"
            }
            return false
        })
        #expect(!model.canSubmit)
        #expect(String(model.editorText.characters) == changedConnector)
    }

    @Test("Moving the cursor never removes a semantic token")
    func cursorMovementDoesNotMutateTokens() throws {
        let context = try makeContext()
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [],
            people: [],
            transitTypes: [],
            modelContext: context
        )

        model.editorText = AttributedString("Stay")
        model.editorTextDidChange()
        model.accept(try #require(
            model.suggestions.first { $0.title == "Stay" }
        ))
        let originalTokens = model.draft.tokens
        let stayRange = try #require(
            String(model.editorText.characters).range(of: "Stay")
        )
        let offset = String(model.editorText.characters).distance(
            from: String(model.editorText.characters).startIndex,
            to: stayRange.lowerBound
        )
        let selectionIndex = model.editorText.characters.index(
            model.editorText.startIndex,
            offsetBy: offset + 1
        )
        model.selection = AttributedTextSelection(
            insertionPoint: selectionIndex
        )
        model.selectionDidChange()

        #expect(model.draft.tokens == originalTokens)
        #expect(String(model.editorText.characters).hasPrefix("Stay"))
        model.editorFocusDidChange(false)

        #expect(model.draft.tokens == originalTokens)
        #expect(String(model.editorText.characters).hasPrefix("Stay"))
    }

    @Test("Tapping a parsed token selects its full range and shows alternatives")
    func tappingTokenSelectsWholeToken() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59)
        )
        let office = Place(
            name: "Office",
            location: Location(latitude: 45.66, longitude: 25.60)
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home, office],
            people: [],
            transitTypes: [],
            modelContext: context
        )

        let sentence = "Stay at Home from 12:00 for 1h"
        model.editorText = AttributedString(sentence)
        model.editorTextDidChange()
        let homeRange = try #require(sentence.range(of: "Home"))
        let homeOffset = sentence.distance(
            from: sentence.startIndex,
            to: homeRange.lowerBound
        )
        let tappedIndex = model.editorText.characters.index(
            model.editorText.startIndex,
            offsetBy: homeOffset + "Home".count
        )
        model.selection = AttributedTextSelection(
            insertionPoint: tappedIndex
        )
        model.selectionDidChange()

        guard case .ranges(let ranges) = model.selection.indices(
            in: model.editorText
        ), let selectedRange = ranges.ranges.first else {
            Issue.record("Expected the complete token to be selected")
            return
        }
        #expect(
            String(model.editorText.characters[selectedRange]) == "Home"
        )
        #expect(model.activeSlot == .location(.visit))
        #expect(model.suggestions.contains { $0.title == "Office" })
        #expect(!model.accessibilityValue.contains("unresolved"))
    }

    @Test("Selecting a preposition neither rewrites text nor adds ghost text")
    func prepositionSelectionIsNative() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59)
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home],
            people: [],
            transitTypes: [],
            modelContext: context
        )
        let sentence = "Stay at Home from 6:00 to 7:00"
        model.editorText = AttributedString(sentence)
        model.editorTextDidChange()
        let originalTokens = model.draft.tokens
        let atOffset = try #require(sentence.range(of: "at")).lowerBound
        let offset = sentence.distance(
            from: sentence.startIndex,
            to: atOffset
        )
        let selectionIndex = model.editorText.characters.index(
            model.editorText.startIndex,
            offsetBy: offset + 1
        )
        model.selection = AttributedTextSelection(
            insertionPoint: selectionIndex
        )
        model.selectionDidChange()

        #expect(String(model.editorText.characters) == sentence)
        #expect(model.draft.tokens == originalTokens)
        #expect(model.activeSlot == .connector)
        #expect(model.editorText.runs.allSatisfy {
            $0.backgroundColor == nil
        })
    }

    @Test("Selecting a visit time connector offers its true alternatives")
    func selectedConnectorShowsClauseAlternatives() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59)
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home],
            people: [],
            transitTypes: [],
            modelContext: context
        )
        let sentence = "Stay at Home from 12:00 to 13:00"
        model.editorText = AttributedString(sentence)
        model.editorTextDidChange()

        let fromRange = try #require(sentence.range(of: "from"))
        let offset = sentence.distance(
            from: sentence.startIndex,
            to: fromRange.lowerBound
        )
        let selectionIndex = model.editorText.characters.index(
            model.editorText.startIndex,
            offsetBy: offset + 1
        )
        model.selection = AttributedTextSelection(
            insertionPoint: selectionIndex
        )
        model.selectionDidChange()

        let titles = Set(model.suggestions.map(\.title))
        #expect(titles == ["at", "from", "since"])

        model.accept(try #require(
            model.suggestions.first { $0.title == "since" }
        ))
        #expect(
            String(model.editorText.characters)
                == "Stay at Home since 12:00 to 13:00"
        )
        #expect(model.canSubmit)
    }

    @Test("Visit duration is legal after a start even before its place")
    func visitDurationDoesNotDependOnLocation() throws {
        let context = try makeContext()
        let beach = Place(
            name: "Beach",
            location: Location(latitude: 44.10, longitude: 28.64)
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [beach],
            people: [],
            transitTypes: [],
            modelContext: context
        )

        let sentence = "Stay from 12:00 "
        model.editorText = AttributedString(sentence)
        model.editorTextDidChange()

        #expect(model.draft.time(.start) != nil)
        #expect(model.draft.location(.visit) == nil)
        #expect(model.suggestions.contains { $0.title == "for" })

        let connectors = GuidedComposerGrammar.legalConnectors(
            entryKind: .placeVisit(description: nil),
            tokens: model.draft.tokens
        )
        #expect(connectors.contains {
            $0.connector == .forDuration && $0.slot == .duration
        })

        let completeSentence = "Stay from 12:00 for 2h at Beach"
        model.editorText = AttributedString(completeSentence)
        model.editorTextDidChange()
        #expect(model.isSyntaxValid)
        #expect(model.canSubmit)
        let resolvedStart = try #require(model.draft.startTime?.date)
        #expect(
            model.draft.endTime?.date
                == resolvedStart.addingTimeInterval(7_200)
        )
    }

    @Test("Visit start connector replacements respect the clause prefix")
    func earlyVisitStartConnectorDoesNotOfferAt() throws {
        let context = try makeContext()
        let beach = Place(
            name: "Beach",
            location: Location(latitude: 44.10, longitude: 28.64)
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [beach],
            people: [],
            transitTypes: [],
            modelContext: context
        )
        let sentence = "Stay from 12:00 at Beach"
        model.editorText = AttributedString(sentence)
        model.editorTextDidChange()

        let fromRange = try #require(sentence.range(of: "from"))
        let offset = sentence.distance(
            from: sentence.startIndex,
            to: fromRange.lowerBound
        )
        let selectionIndex = model.editorText.characters.index(
            model.editorText.startIndex,
            offsetBy: offset + 1
        )
        model.selection = AttributedTextSelection(
            insertionPoint: selectionIndex
        )
        model.selectionDidChange()

        #expect(Set(model.suggestions.map(\.title)) == ["from", "since"])
        #expect(!model.suggestions.contains { $0.title == "at" })

        model.accept(try #require(
            model.suggestions.first { $0.title == "since" }
        ))
        #expect(
            String(model.editorText.characters)
                == "Stay since 12:00 at Beach"
        )
        #expect(model.isSyntaxValid)
    }

    @Test("Selecting a people separator offers comma, and, and ampersand")
    func selectedPeopleSeparatorShowsAlternatives() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59)
        )
        let emma = Person(name: "Emma")
        let ana = Person(name: "Ana")
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home],
            people: [emma, ana],
            transitTypes: [],
            modelContext: context
        )
        let sentence =
            "Stay at Home from 12:00 to 13:00 with Emma, Ana"
        model.editorText = AttributedString(sentence)
        model.editorTextDidChange()

        let commaRange = try #require(sentence.range(of: ","))
        let offset = sentence.distance(
            from: sentence.startIndex,
            to: commaRange.lowerBound
        )
        let selectionIndex = model.editorText.characters.index(
            model.editorText.startIndex,
            offsetBy: offset
        )
        model.selection = AttributedTextSelection(
            insertionPoint: selectionIndex
        )
        model.selectionDidChange()

        #expect(Set(model.suggestions.map(\.title)) == [",", "and", "&"])
        model.accept(try #require(
            model.suggestions.first { $0.title == "and" }
        ))
        #expect(
            String(model.editorText.characters)
                == "Stay at Home from 12:00 to 13:00 with Emma and Ana"
        )
        #expect(model.canSubmit)
    }

    @Test("Select all and delete resets the composer")
    func selectAllDeleteResetsComposer() throws {
        let context = try makeContext()
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [],
            people: [],
            transitTypes: [],
            modelContext: context
        )
        model.accept(
            ComposerSuggestion(
                id: "test-select-all",
                title: "Stay from",
                subtitle: nil,
                systemImage: "clock",
                kind: .macro(
                    tokens: [
                        token("Stay", .leading(.placeVisit(description: nil))),
                        token("from", .connector(.from)),
                    ],
                    nextSlot: .time(.start)
                ),
                score: 10_000
            )
        )
        let fullRange = model.editorText.startIndex..<model.editorText.endIndex
        model.selection = AttributedTextSelection(range: fullRange)
        model.selectionDidChange()

        #expect(model.draft.tokens.count == 2)

        model.editorText = AttributedString()
        model.editorTextDidChange()

        #expect(model.isIdle)
        #expect(model.draft.tokens.isEmpty)
        #expect(model.activeSlot == .leading)
        #expect(!model.shouldPresentSuggestions)
        #expect(String(model.editorText.characters).isEmpty)

        model.editorText = AttributedString("Stay")
        model.editorTextDidChange()
        model.accept(try #require(
            model.suggestions.first { $0.title == "Stay" }
        ))
        model.selection = AttributedTextSelection(
            range: model.editorText.startIndex..<model.editorText.endIndex
        )
        model.selectionDidChange()
        #expect(model.draft.tokens.count == 1)

        model.editorText = AttributedString()
        model.editorTextDidChange()
        #expect(model.isIdle)
    }

    @Test("Clearing a draft cancels pending place search state")
    func clearCancelsPendingPlaceSearch() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59)
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home],
            people: [],
            transitTypes: [],
            modelContext: context
        )

        model.editorText = AttributedString("Stay at zz")
        model.editorTextDidChange()
        #expect(model.isSearchingPlaces)

        model.clearCurrentDraft()

        #expect(!model.isSearchingPlaces)
        #expect(model.isIdle)
        #expect(!model.shouldPresentSuggestions)
    }

    @Test("Clock suggestions normalize display and space accepts a full time")
    func clockDisplayAndSpaceAcceptance() throws {
        let context = try makeContext()
        let selectedDay = TimelineDayKey(
            year: 2026,
            month: 7,
            day: 18
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: selectedDay,
            places: [],
            people: [],
            transitTypes: [],
            modelContext: context
        )
        model.accept(
            ComposerSuggestion(
                id: "test-time-prefix",
                title: "Stay from",
                subtitle: nil,
                systemImage: "clock",
                kind: .macro(
                    tokens: [
                        token("Stay", .leading(.placeVisit(description: nil))),
                        token("from", .connector(.from)),
                    ],
                    nextSlot: .time(.start)
                ),
                score: 10_000
            )
        )

        model.editorText = AttributedString("Stay from 6")
        model.editorTextDidChange()
        #expect(String(model.editorText.characters) == "Stay from 6")
        let sixSuggestion = try #require(model.suggestions.first)
        let sixDate = try #require(
            GuidedComposerTimeParser.parseTime(
                "6",
                role: .start,
                selectedDay: selectedDay,
                timeZone: .current
            )
        )
        let normalizedSix = GuidedComposerTimeParser.displayTime(
            sixDate,
            timeZone: .current
        )
        #expect(sixSuggestion.title == normalizedSix)
        model.accept(sixSuggestion)
        #expect(model.draft.time(.start)?.date == sixDate)
        #expect(model.draft.tokens.contains {
            if case .time(_, .start) = $0.value {
                return $0.displayText == normalizedSix
            }
            return false
        })

        model.clearCurrentDraft()
        model.accept(
            ComposerSuggestion(
                id: "test-time-prefix-again",
                title: "Stay from",
                subtitle: nil,
                systemImage: "clock",
                kind: .macro(
                    tokens: [
                        token("Stay", .leading(.placeVisit(description: nil))),
                        token("from", .connector(.from)),
                    ],
                    nextSlot: .time(.start)
                ),
                score: 10_000
            )
        )
        model.editorText = AttributedString("Stay from 6:45")
        model.editorTextDidChange()
        model.editorText = AttributedString("Stay from 6:45 ")
        model.editorTextDidChange()

        let sixFortyFive = try #require(
            GuidedComposerTimeParser.parseTime(
                "6:45",
                role: .start,
                selectedDay: selectedDay,
                timeZone: .current
            )
        )
        #expect(model.draft.time(.start)?.date == sixFortyFive)
        #expect(model.activeSlot == .connector)
        #expect(model.activeQuery.isEmpty)
    }

    @Test("A selected transit origin prioritizes its destination clause")
    func transitOriginPrioritizesDestination() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59)
        )
        let poiana = Place(
            name: "Home - Poiana",
            location: Location(latitude: 45.59, longitude: 25.55)
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home, poiana],
            people: [],
            transitTypes: [
                TransitType(canonicalName: "Car", aliases: ["car"]),
            ],
            modelContext: context
        )

        model.editorText = AttributedString("Car")
        model.editorTextDidChange()
        model.accept(try #require(model.suggestions.first))

        model.editorText = AttributedString("Car from ")
        model.editorTextDidChange()
        let poianaSuggestion = try #require(
            model.suggestions.first { $0.title == "Home - Poiana" }
        )
        model.accept(poianaSuggestion)

        #expect(model.activeSlot == .connector)
        #expect(model.suggestions.first?.title == "to")
    }

    @Test("Editing a time seeds the manual picker from that token")
    func editingTimeSeedsPicker() throws {
        let context = try makeContext()
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [],
            people: [],
            transitTypes: [
                TransitType(canonicalName: "Bolt", aliases: ["bolt"]),
            ],
            modelContext: context
        )
        model.editorText = AttributedString("Bolt ")
        model.editorTextDidChange()

        let origin = location(
            "Home",
            latitude: 45.65,
            longitude: 25.59
        )
        let destination = location(
            "Gara Brașov",
            latitude: 45.66,
            longitude: 25.61
        )
        let start = date("2026-07-18T06:41:00+03:00")
        let route = GuidedComposerRouteInference.routeSuggestion(
            id: "test-picker-route",
            origin: origin,
            destination: destination,
            start: start,
            end: date("2026-07-18T06:49:00+03:00"),
            timeSource: .history,
            durationSource: .mapkitCarFallback,
            subtitle: "Test route",
            score: 10_000
        )
        model.accept(route)
        #expect(model.draft.time(.start)?.source == .history)
        #expect(
            model.draft.time(.start)?.durationSource
                == .mapkitCarFallback
        )

        let startToken = try #require(model.draft.tokens.first {
            if case .time(_, .start) = $0.value { return true }
            return false
        })
        let renderedText = String(model.editorText.characters)
        let renderedRange = try #require(
            renderedText.range(of: startToken.displayText)
        )
        let offset = renderedText.distance(
            from: renderedText.startIndex,
            to: renderedRange.lowerBound
        )
        let selectionIndex = model.editorText.characters.index(
            model.editorText.startIndex,
            offsetBy: offset + 1
        )
        model.selection = AttributedTextSelection(
            insertionPoint: selectionIndex
        )
        model.selectionDidChange()

        #expect(model.activeSlot == .time(.start))
        #expect(model.suggestedPickerDate(for: .start) == start)
        #expect(model.pickerTimeZone(for: .start) == zone)
        #expect(model.pickerSeedID(for: .start) == startToken.id)
    }

    @Test("Spaces keep an arbitrary description active until Use is accepted")
    func descriptionSpaceDoesNotResetSuggestions() throws {
        let context = try makeContext()
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [],
            people: [],
            transitTypes: [
                TransitType(canonicalName: "Bicycle", aliases: ["bike"]),
            ],
            modelContext: context
        )

        model.editorText = AttributedString("watch ")
        model.editorTextDidChange()

        #expect(model.activeSlot == .leading)
        #expect(model.activeQuery == "watch")
        #expect(model.draft.entryKind == nil)
        #expect(model.suggestions.contains {
            $0.title == "Use “watch”"
        })
        #expect(!model.suggestions.contains { $0.title == "Stay" })
        #expect(String(model.editorText.characters) == "watch ")
    }

    @Test("Descriptions may begin with a reserved entry type")
    func descriptionCanExtendReservedLeadingPhrase() throws {
        let context = try makeContext()
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [],
            people: [],
            transitTypes: [
                TransitType(canonicalName: "Bicycle", aliases: ["bike"]),
            ],
            modelContext: context
        )

        model.editorText = AttributedString("Bike repair ")
        model.editorTextDidChange()

        #expect(model.draft.entryKind == nil)
        #expect(model.activeSlot == .leading)
        #expect(model.suggestions.contains {
            $0.title == "Use “Bike repair”"
        })
        #expect(String(model.editorText.characters) == "Bike repair ")
    }

    @Test("An exact place keeps longer matches beside legal connectors")
    func exactPlaceMixedSuggestions() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59)
        )
        let poiana = Place(
            name: "Home - Poiana",
            location: Location(latitude: 45.59, longitude: 25.55)
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home, poiana],
            people: [],
            transitTypes: [],
            modelContext: context
        )

        model.editorText = AttributedString("Stay at Home ")
        model.editorTextDidChange()

        #expect(model.draft.location(.visit)?.displayName == "Home")
        #expect(model.activeSlot == .connector)
        #expect(model.suggestions.contains {
            $0.title == "Home - Poiana"
        })
        #expect(model.suggestions.contains {
            $0.title == "at" && $0.subtitle == "Start time"
        })
        #expect(String(model.editorText.characters) == "Stay at Home ")
    }

    @Test("A longer place continuation replaces the shorter exact match")
    func placeContinuationReplacesSoftResolution() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59)
        )
        let poiana = Place(
            name: "Home - Poiana",
            location: Location(latitude: 45.59, longitude: 25.55)
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home, poiana],
            people: [],
            transitTypes: [],
            modelContext: context
        )
        model.editorText = AttributedString("Stay at Home ")
        model.editorTextDidChange()

        model.accept(try #require(
            model.suggestions.first { $0.title == "Home - Poiana" }
        ))

        #expect(
            String(model.editorText.characters) == "Stay at Home - Poiana "
        )
        #expect(model.draft.location(.visit)?.savedPlaceID == poiana.id)
    }

    @Test("A longer person continuation replaces the shorter exact match")
    func personContinuationReplacesSoftResolution() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59)
        )
        let emma = Person(name: "Emma")
        let emmaMaria = Person(name: "Emma Maria")
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home],
            people: [emma, emmaMaria],
            transitTypes: [],
            modelContext: context
        )
        model.editorText = AttributedString(
            "Stay at Home from 12:00 to 13:00 with Emma "
        )
        model.editorTextDidChange()

        model.accept(try #require(
            model.suggestions.first { $0.title == "Emma Maria" }
        ))

        #expect(
            String(model.editorText.characters)
                == "Stay at Home from 12:00 to 13:00 with Emma Maria "
        )
        #expect(model.draft.people.map(\.id) == [emmaMaria.id])
    }

    @Test("An ambiguous person connector requires an explicit split")
    func ambiguousPersonConnectorSplit() throws {
        let context = try makeContext()
        let emma = Person(name: "Emma")
        let emmaMaria = Person(name: "Emma Maria")
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [],
            people: [emma, emmaMaria],
            transitTypes: [],
            modelContext: context
        )

        model.editorText = AttributedString("Stay with Emma at ")
        model.editorTextDidChange()

        #expect(model.activeSlot == .person)
        #expect(!model.isSyntaxValid)
        #expect(model.suggestions.contains {
            $0.title == "Emma · at"
        })
        #expect(model.suggestions.contains {
            $0.title == "Add “Emma at”"
        })
        #expect(!model.suggestions.contains {
            $0.subtitle == "Visit place"
        })

        let split = try #require(
            model.suggestions.first { $0.title == "Emma · at" }
        )
        model.accept(split)

        #expect(model.draft.people.map(\.name) == ["Emma"])
        #expect(model.activeSlot == .location(.visit))
        #expect(String(model.editorText.characters) == "Stay with Emma at ")
    }

    @Test("A soft exact person can grow into a longer match")
    func softExactPersonCanGrow() throws {
        let context = try makeContext()
        let emma = Person(name: "Emma")
        let emmaMaria = Person(name: "Emma Maria")
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [],
            people: [emma, emmaMaria],
            transitTypes: [],
            modelContext: context
        )

        model.editorText = AttributedString("Stay with Emma ")
        model.editorTextDidChange()
        #expect(model.draft.people.map(\.name) == ["Emma"])
        #expect(model.suggestions.contains { $0.title == "Emma Maria" })

        model.editorText = AttributedString("Stay with Emma M")
        model.editorTextDidChange()

        #expect(model.draft.people.isEmpty)
        #expect(model.activeSlot == .person)
        #expect(model.activeQuery == "Emma M")
        #expect(model.suggestions.contains { $0.title == "Emma Maria" })
    }

    @Test("A fully typed exact person remains an autocomplete result")
    func exactPersonRemainsSuggestedWhileEditing() throws {
        let context = try makeContext()
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [],
            people: [Person(name: "Emma")],
            transitTypes: [],
            modelContext: context
        )

        model.editorText = AttributedString("Stay with Emma")
        model.editorTextDidChange()

        #expect(model.activeSlot == .person)
        #expect(model.activeQuery == "Emma")
        #expect(model.suggestions.contains { $0.title == "Emma" })
        #expect(!model.suggestions.contains {
            $0.title == "Add “Emma”"
        })
    }

    @Test("Additional people are inserted as natural comma-list items")
    func additionalPeopleUseListMacro() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: zone.identifier
            )
        )
        let emma = Person(name: "Emma")
        let ana = Person(name: "Ana")
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home],
            people: [emma, ana],
            transitTypes: [],
            modelContext: context
        )
        model.editorText = AttributedString(
            "Stay at Home from 12:00 to 13:00 with Emma "
        )
        model.editorTextDidChange()

        #expect(model.canSubmit)
        let suggestion = try #require(
            model.suggestions.first { $0.title == ", Ana" }
        )
        model.accept(suggestion)

        #expect(model.canSubmit)
        #expect(Set(model.draft.people.map(\.id)) == Set([emma.id, ana.id]))
        #expect(
            String(model.editorText.characters)
                == "Stay at Home from 12:00 to 13:00 with Emma, Ana "
        )
    }

    @Test("With clauses accept comma, and, and ampersand person lists")
    func personListSeparators() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: zone.identifier
            )
        )
        let emma = Person(name: "Emma")
        let ana = Person(name: "Ana")
        let mia = Person(name: "Mia")
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home],
            people: [emma, ana, mia],
            transitTypes: [],
            modelContext: context
        )

        for separator in [", ", " and ", " & "] {
            model.editorText = AttributedString(
                "Stay at Home from 12:00 to 13:00 with Emma"
                    + separator
                    + "Ana"
            )
            model.editorTextDidChange()

            #expect(model.isSyntaxValid)
            #expect(model.canSubmit)
            #expect(
                Set(model.draft.people.map(\.id)) == Set([emma.id, ana.id])
            )
        }

        model.editorText = AttributedString(
            "Stay at Home from 12:00 to 13:00 with Emma,Ana and Mia"
        )
        model.editorTextDidChange()

        #expect(model.isSyntaxValid)
        #expect(model.canSubmit)
        #expect(
            Set(model.draft.people.map(\.id))
                == Set([emma.id, ana.id, mia.id])
        )

        model.editorText = AttributedString(
            "Stay at Home with Emma, Ana at 12:00 to 13:00"
        )
        model.editorTextDidChange()

        #expect(model.isSyntaxValid)
        #expect(model.canSubmit)
        #expect(Set(model.draft.people.map(\.id)) == Set([emma.id, ana.id]))
    }

    @Test("Person separators preserve entity-name ambiguity")
    func personListSeparatorAmbiguity() throws {
        let context = try makeContext()
        let emma = Person(name: "Emma")
        let emmaMaria = Person(name: "Emma Maria")
        let ana = Person(name: "Ana")
        let duo = Person(name: "Simon and Garfunkel")
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [],
            people: [emma, emmaMaria, ana, duo],
            transitTypes: [],
            modelContext: context
        )

        model.editorText = AttributedString("Stay with Emma and Ana")
        model.editorTextDidChange()

        #expect(!model.isSyntaxValid)
        #expect(model.draft.people.map(\.id) == [emma.id])
        #expect(model.suggestions.contains { $0.title == "Emma · and" })

        model.editorText = AttributedString("Stay with Simon and Garfunkel")
        model.editorTextDidChange()

        #expect(model.isSyntaxValid)
        #expect(model.draft.people.map(\.id) == [duo.id])
    }

    @Test("Only one with clause is allowed")
    func repeatedWithClauseIsRejected() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: zone.identifier
            )
        )
        let afi = Place(
            name: "AFI",
            location: Location(
                latitude: 45.66,
                longitude: 25.61,
                timeZoneIdentifier: zone.identifier
            )
        )
        let emma = Person(name: "Emma")
        let ana = Person(name: "Ana")
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home, afi],
            people: [emma, ana],
            transitTypes: [
                TransitType(canonicalName: "Bolt", aliases: ["bolt"]),
            ],
            modelContext: context
        )

        model.editorText = AttributedString(
            "Stay at Home with Emma "
        )
        model.editorTextDidChange()

        #expect(!model.suggestions.contains { $0.title == "with" })
        #expect(model.suggestions.contains { $0.title == ", Ana" })

        model.editorText = AttributedString(
            "Stay at Home with Emma from 12:00 to 13:00 "
        )
        model.editorTextDidChange()

        #expect(model.canSubmit)
        #expect(!model.suggestions.contains { $0.title == "with" })

        model.editorText = AttributedString(
            "Stay at Home with Emma with Ana from 12:00 to 13:00"
        )
        model.editorTextDidChange()

        #expect(!model.isSyntaxValid)
        #expect(!model.canSubmit)

        model.editorText = AttributedString(
            "Bolt from Home to AFI with Emma with Ana "
                + "from 12:00 to 13:00"
        )
        model.editorTextDidChange()

        #expect(!model.isSyntaxValid)
        #expect(!model.canSubmit)
    }

    @Test("Duplicate exact people remain unresolved")
    func duplicateExactPeopleRequireSelection() throws {
        let context = try makeContext()
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [],
            people: [
                Person(name: "Emma"),
                Person(name: "Emma"),
            ],
            transitTypes: [],
            modelContext: context
        )

        model.editorText = AttributedString("Stay with Emma ")
        model.editorTextDidChange()

        #expect(model.draft.people.isEmpty)
        #expect(model.activeSlot == .person)
        #expect(model.activeQuery == "Emma")
        #expect(
            model.suggestions.filter { $0.title == "Emma" }.count == 2
        )
        #expect(!model.suggestions.contains {
            $0.subtitle == "Visit place"
        })
    }

    @Test("Explicit descriptions may contain connector words")
    func descriptionMayContainConnectorWords() throws {
        let context = try makeContext()
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [],
            people: [],
            transitTypes: [],
            modelContext: context
        )

        model.editorText = AttributedString("Meet at Dawn ")
        model.editorTextDidChange()

        #expect(model.draft.entryKind == nil)
        let useDescription = try #require(
            model.suggestions.first {
                $0.title == "Use “Meet at Dawn”"
            }
        )
        model.accept(useDescription)

        #expect(
            model.draft.entryKind
                == .placeVisit(description: "Meet at Dawn")
        )
        #expect(String(model.editorText.characters) == "Meet at Dawn ")
        #expect(model.activeSlot == .connector)
    }

    @Test("Committed entity names may contain connector words")
    func committedPlaceContainingConnectorParsesAsOneValue() {
        let home = location(
            "Home",
            latitude: 45.65,
            longitude: 25.59
        )
        let homeAtBeach = location(
            "Home at Beach",
            latitude: 44.10,
            longitude: 28.64
        )
        let text = "Stay at Home at Beach from 12:00 to 13:00"
        let snapshot = GuidedComposerSemanticParser.parse(
            GuidedComposerSemanticParser.Input(
                text: text,
                selection: text.count..<text.count,
                bindings: [
                    ComposerSemanticBinding(
                        token: token(
                            "Home at Beach",
                            .location(homeAtBeach, .visit)
                        ),
                        range: 8..<21
                    ),
                ],
                transitTypes: [],
                locations: [home, homeAtBeach],
                people: [],
                selectedDay: TimelineDayKey(
                    year: 2026,
                    month: 7,
                    day: 18
                )
            )
        )
        let draft = ComposerDraft(tokens: snapshot.tokens)

        #expect(snapshot.isSyntaxValid)
        #expect(draft.canSubmit)
        #expect(draft.location(.visit)?.id == homeAtBeach.id)
    }

    @Test("Connector words stay in an unresolved person query")
    func unresolvedPersonKeepsConnectorWords() throws {
        let context = try makeContext()
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [],
            people: [
                Person(name: "Emma Andrea"),
                Person(name: "Emma Maria"),
            ],
            transitTypes: [],
            modelContext: context
        )

        model.editorText = AttributedString("Stay with Emma at ")
        model.editorTextDidChange()

        #expect(model.draft.people.isEmpty)
        #expect(model.activeSlot == .person)
        #expect(model.activeQuery == "Emma at")
        #expect(model.suggestions.contains {
            $0.title == "Add “Emma at”"
        })
        #expect(!model.suggestions.contains {
            $0.title.contains("· at")
        })
    }

    @Test("Visit grammar supports a place-adjacent start at")
    func visitSecondAtIsStartTime() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: zone.identifier
            )
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home],
            people: [],
            transitTypes: [],
            modelContext: context
        )

        let sentence = "Stay at Home at 12:00 for 2h"
        model.editorText = AttributedString(sentence)
        model.editorTextDidChange()

        #expect(model.isSyntaxValid)
        #expect(model.canSubmit)
        #expect(model.draft.location(.visit)?.displayName == "Home")
        #expect(model.draft.time(.start) != nil)
        #expect(model.draft.duration == TimeInterval(7_200))
        #expect(String(model.editorText.characters) == sentence)
    }

    @Test("Connector grammar keeps duration and time anchors exclusive")
    func durationAndTimeConnectorMatrix() {
        let home = location(
            "Home",
            latitude: 45.65,
            longitude: 25.59
        )
        let beach = location(
            "Beach",
            latitude: 44.10,
            longitude: 28.64
        )
        let startValue = ComposerTimeValue(
            date: date("2026-07-18T19:25:00+03:00"),
            timeZoneIdentifier: zone.identifier,
            source: .explicit
        )
        let endValue = ComposerTimeValue(
            date: date("2026-07-18T19:40:00+03:00"),
            timeZoneIdentifier: zone.identifier,
            source: .explicit
        )
        let duration = token(
            "15 min",
            .duration(
                ComposerDurationValue(
                    interval: 15 * 60,
                    source: .manualOverride
                )
            )
        )
        let visitLeading = token(
            "Stay",
            .leading(.placeVisit(description: nil))
        )
        let transitLeading = token(
            "Bolt",
            .leading(.transit(canonicalName: "Bolt"))
        )
        let visitLocation = token(
            "Home",
            .location(home, .visit)
        )
        let origin = token("Home", .location(home, .origin))
        let destination = token(
            "Beach",
            .location(beach, .destination)
        )
        let start = token("19:25", .time(startValue, .start))
        let end = token("19:40", .time(endValue, .end))

        func connectors(
            kind: ComposerEntryKind,
            tokens: [ComposerToken]
        ) -> Set<ComposerConnector> {
            Set(
                GuidedComposerGrammar.legalConnectors(
                    entryKind: kind,
                    tokens: tokens
                ).map(\.connector)
            )
        }

        let visitKind = ComposerEntryKind.placeVisit(description: nil)
        let visitWithStartBeforePlace = connectors(
            kind: visitKind,
            tokens: [visitLeading, start]
        )
        #expect(visitWithStartBeforePlace.contains(.at))
        #expect(visitWithStartBeforePlace.contains(.forDuration))
        #expect(!visitWithStartBeforePlace.contains(.from))

        let visitAtPlace = connectors(
            kind: visitKind,
            tokens: [visitLeading, visitLocation]
        )
        #expect(visitAtPlace.contains(.forDuration))
        #expect(visitAtPlace.contains(.from))
        #expect(visitAtPlace.contains(.to))

        let completeVisit = connectors(
            kind: visitKind,
            tokens: [visitLeading, visitLocation, start, end]
        )
        #expect(!completeVisit.contains(.forDuration))
        #expect(!completeVisit.contains(.from))
        #expect(!completeVisit.contains(.to))
        #expect(!completeVisit.contains(.at))

        let visitWithDerivedEnd = connectors(
            kind: visitKind,
            tokens: [visitLeading, visitLocation, start, duration]
        )
        #expect(visitWithDerivedEnd == Set([.with]))

        let transitKind = ComposerEntryKind.transit(
            canonicalName: "Bolt"
        )
        let transitEndpoints = [
            transitLeading,
            origin,
            destination,
        ]
        let withoutTime = connectors(
            kind: transitKind,
            tokens: transitEndpoints
        )
        #expect(!withoutTime.contains(.forDuration))
        #expect(withoutTime.contains(.from))
        #expect(withoutTime.contains(.to))

        let withStart = connectors(
            kind: transitKind,
            tokens: transitEndpoints + [start]
        )
        #expect(withStart.contains(.forDuration))
        #expect(withStart.contains(.to))
        #expect(!withStart.contains(.from))

        let completeTransit = connectors(
            kind: transitKind,
            tokens: transitEndpoints + [start, end]
        )
        #expect(completeTransit == Set([.with]))

        let transitWithDerivedEnd = connectors(
            kind: transitKind,
            tokens: transitEndpoints + [start, duration]
        )
        #expect(transitWithDerivedEnd == Set([.with]))
    }

    @Test("Connector grammar is stable across every visit interval state")
    func visitConnectorStateSpace() {
        let home = location(
            "Home",
            latitude: 45.65,
            longitude: 25.59
        )
        let startValue = ComposerTimeValue(
            date: date("2026-07-18T12:00:00+03:00"),
            timeZoneIdentifier: zone.identifier,
            source: .explicit
        )
        let endValue = ComposerTimeValue(
            date: date("2026-07-18T13:00:00+03:00"),
            timeZoneIdentifier: zone.identifier,
            source: .explicit
        )
        let leading = token(
            "Stay",
            .leading(.placeVisit(description: nil))
        )
        let place = token("Home", .location(home, .visit))
        let start = token("12:00", .time(startValue, .start))
        let end = token("13:00", .time(endValue, .end))
        let duration = token(
            "1 hr",
            .duration(
                ComposerDurationValue(
                    interval: 3_600,
                    source: .manualOverride
                )
            )
        )

        func key(
            _ connector: ComposerConnector,
            _ slot: ComposerSlot
        ) -> String {
            "\(connector.rawValue)|\(slot)"
        }

        for hasPlace in [false, true] {
            for hasStart in [false, true] {
                for hasEnd in [false, true] {
                    for hasDuration in [false, true] {
                        var tokens = [leading]
                        if hasStart { tokens.append(start) }
                        if hasEnd { tokens.append(end) }
                        if hasDuration { tokens.append(duration) }
                        if hasPlace { tokens.append(place) }

                        let actual = Set(
                            GuidedComposerGrammar.legalConnectors(
                                entryKind: .placeVisit(description: nil),
                                tokens: tokens
                            ).map { key($0.connector, $0.slot) }
                        )
                        let intervalResolved = (hasStart && hasEnd)
                            || (hasDuration && (hasStart || hasEnd))
                        let needsStart = !hasStart && !intervalResolved
                        let needsEnd = !hasEnd && !intervalResolved
                        var expected = Set([key(.with, .person)])

                        if hasPlace {
                            if needsStart {
                                expected.insert(key(.at, .time(.start)))
                            }
                        } else {
                            expected.insert(key(.at, .location(.visit)))
                        }
                        if needsStart {
                            expected.insert(key(.from, .time(.start)))
                            expected.insert(key(.since, .time(.start)))
                        }
                        if needsEnd {
                            expected.insert(key(.to, .time(.end)))
                            expected.insert(key(.until, .time(.end)))
                        }
                        if !hasDuration,
                           !(hasStart && hasEnd),
                           hasPlace || hasStart || hasEnd {
                            expected.insert(key(.forDuration, .duration))
                        }

                        #expect(
                            actual == expected,
                            "place=\(hasPlace), start=\(hasStart), end=\(hasEnd), duration=\(hasDuration)"
                        )
                    }
                }
            }
        }
    }

    @Test("A duration after two explicit transit times is invalid")
    func transitDurationAfterBothTimesIsInvalid() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.59)
        )
        let beach = Place(
            name: "Beach",
            location: Location(latitude: 44.10, longitude: 28.64)
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home, beach],
            people: [],
            transitTypes: [
                TransitType(canonicalName: "Bolt", aliases: ["bolt"]),
            ],
            modelContext: context
        )

        model.editorText = AttributedString(
            "Bolt from Home at 19:25 to Beach at 19:40 for 1 hr"
        )
        model.editorTextDidChange()

        #expect(!model.isSyntaxValid)
        #expect(!model.canSubmit)
    }

    @Test("An explicit transit start shows only relative end times")
    func explicitTransitStartUsesRelativeEndSuggestions() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: zone.identifier
            )
        )
        let beach = Place(
            name: "Beach",
            location: Location(
                latitude: 44.10,
                longitude: 28.64,
                timeZoneIdentifier: zone.identifier
            )
        )
        context.insert(home)
        context.insert(beach)
        context.insert(
            visit(
                place: home,
                start: "2026-07-18T18:00:00+03:00",
                end: "2026-07-18T19:00:00+03:00"
            )
        )
        context.insert(
            visit(
                place: beach,
                start: "2026-07-18T20:00:00+03:00",
                end: "2026-07-18T21:00:00+03:00"
            )
        )
        try context.save()

        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home, beach],
            people: [],
            transitTypes: [
                TransitType(canonicalName: "Bolt", aliases: ["bolt"]),
            ],
            modelContext: context
        )
        model.editorText = AttributedString(
            "Bolt from Home to Beach from 19:25 to "
        )
        model.editorTextDidChange()

        #expect(model.activeSlot == .time(.end))
        let suggestedEndDates = model.suggestions.compactMap {
            suggestion -> Date? in
            guard case .value(let tokens, _) = suggestion.kind else {
                return nil
            }
            return tokens.compactMap {
                guard case .time(let value, .end) = $0.value else {
                    return nil
                }
                #expect(value.source == .explicit)
                return value.date
            }.first
        }
        #expect(Set(suggestedEndDates) == Set([
            date("2026-07-18T19:35:00+03:00"),
            date("2026-07-18T19:40:00+03:00"),
            date("2026-07-18T19:55:00+03:00"),
            date("2026-07-18T20:10:00+03:00"),
            date("2026-07-18T20:25:00+03:00"),
        ]))
        #expect(!model.suggestions.contains {
            $0.id.contains("route-gap-")
                || $0.id.contains("route-gps-")
        })
    }

    @Test("A custom route suggests its origin visit's free end time")
    func customRouteSuggestsOriginBoundaryTime() throws {
        let context = try makeContext()
        let placeA = Place(
            name: "Place A",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: zone.identifier
            )
        )
        let placeB = Place(
            name: "Place B",
            location: Location(
                latitude: 45.70,
                longitude: 25.65,
                timeZoneIdentifier: zone.identifier
            )
        )
        let placeC = Place(
            name: "Place C",
            location: Location(
                latitude: 45.75,
                longitude: 25.70,
                timeZoneIdentifier: zone.identifier
            )
        )
        for place in [placeA, placeB, placeC] { context.insert(place) }
        context.insert(visit(
            place: placeA,
            start: "2026-07-18T09:00:00+03:00",
            end: "2026-07-18T10:00:00+03:00"
        ))
        context.insert(visit(
            place: placeB,
            start: "2026-07-18T12:00:00+03:00",
            end: "2026-07-18T13:00:00+03:00"
        ))
        try context.save()

        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [placeA, placeB, placeC],
            people: [],
            transitTypes: [
                TransitType(canonicalName: "Walk", aliases: ["walk"]),
            ],
            modelContext: context
        )
        model.editorText = AttributedString(
            "Walk from Place A to Place C from "
        )
        model.editorTextDidChange()

        #expect(model.activeSlot == .time(.start))
        #expect(model.suggestions.contains { suggestion in
            guard suggestion.id.hasPrefix("time-timeline-start-"),
                  case .value(let tokens, _) = suggestion.kind else {
                return false
            }
            return tokens.contains {
                guard case .time(let value, .start) = $0.value else {
                    return false
                }
                return value.date
                    == date("2026-07-18T10:00:00+03:00")
                    && value.source == .history
            }
        })
    }

    @Test("A visit duration may precede its start boundary")
    func visitDurationAfterPlaceBeforeStart() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: zone.identifier
            )
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home],
            people: [],
            transitTypes: [],
            modelContext: context
        )

        let sentence = "Stay at Home for 2h from 12:00"
        model.editorText = AttributedString(sentence)
        model.editorTextDidChange()

        #expect(model.isSyntaxValid)
        #expect(model.canSubmit)
        #expect(model.draft.duration == TimeInterval(7_200))
        #expect(model.draft.time(.start) != nil)
        #expect(model.draft.endTime?.date.timeIntervalSince(
            try #require(model.draft.startTime?.date)
        ) == TimeInterval(7_200))
    }

    @Test("Duration suggestions offer hours and minutes and normalize acceptance")
    func durationSuggestionsNormalizeAcceptance() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: zone.identifier
            )
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home],
            people: [],
            transitTypes: [],
            modelContext: context
        )

        model.editorText = AttributedString("Stay at Home for 2")
        model.editorTextDidChange()

        #expect(model.suggestions.contains { $0.title == "2 hr" })
        #expect(model.suggestions.contains { $0.title == "2 min" })
        model.accept(try #require(
            model.suggestions.first { $0.title == "2 hr" }
        ))

        #expect(
            String(model.editorText.characters).contains("for 2 hr")
        )
        #expect(model.draft.duration == TimeInterval(7_200))
    }

    @Test("A visit start at may follow a people clause")
    func visitSecondAtAfterPeople() throws {
        let context = try makeContext()
        let reynaBeach = Place(
            name: "Reyna Beach",
            location: Location(
                latitude: 44.10,
                longitude: 28.64,
                timeZoneIdentifier: zone.identifier
            )
        )
        let emma = Person(name: "Emma")
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [reynaBeach],
            people: [emma],
            transitTypes: [],
            modelContext: context
        )

        model.editorText = AttributedString("Coffee ")
        model.editorTextDidChange()
        model.accept(try #require(
            model.suggestions.first { $0.title == "Use “Coffee”" }
        ))

        let sentence =
            "Coffee at Reyna Beach with Emma at 16:00 for 1h"
        model.editorText = AttributedString(sentence)
        model.editorTextDidChange()

        #expect(model.isSyntaxValid)
        #expect(model.canSubmit)
        #expect(model.draft.location(.visit)?.displayName == "Reyna Beach")
        #expect(model.draft.people.map(\.name) == ["Emma"])
        #expect(model.draft.time(.start) != nil)
        #expect(model.draft.duration == TimeInterval(3_600))
        #expect(String(model.editorText.characters) == sentence)
    }

    @Test("An unfinished visit at offers connector and person parses")
    func visitAtOffersConnectorAndPersonInterpretations() throws {
        let context = try makeContext()
        let reynaBeach = Place(
            name: "Reyna Beach",
            location: Location(
                latitude: 44.10,
                longitude: 28.64,
                timeZoneIdentifier: zone.identifier
            )
        )
        let emma = Person(name: "Emma")
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [reynaBeach],
            people: [emma],
            transitTypes: [],
            modelContext: context
        )

        model.editorText = AttributedString("Coffee ")
        model.editorTextDidChange()
        model.accept(try #require(
            model.suggestions.first { $0.title == "Use “Coffee”" }
        ))

        let sentence = "Coffee at Reyna Beach with Emma at"
        model.editorText = AttributedString(sentence)
        model.editorTextDidChange()

        #expect(model.activeSlot == .person)
        #expect(model.suggestions.contains {
            $0.title == "at" && $0.subtitle == "Start time"
        })
        #expect(model.suggestions.contains {
            $0.title == "Add “Emma at”"
        })

        model.accept(try #require(
            model.suggestions.first {
                $0.title == "at" && $0.subtitle == "Start time"
            }
        ))

        #expect(String(model.editorText.characters) == sentence + " ")
        #expect(model.activeSlot == .time(.start))
        #expect(model.draft.people.map(\.name) == ["Emma"])
    }

    @Test("Transit grammar supports endpoints followed by a time interval")
    func transitRepeatedFromToInterval() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: zone.identifier
            )
        )
        let afi = Place(
            name: "AFI",
            location: Location(
                latitude: 45.66,
                longitude: 25.61,
                timeZoneIdentifier: zone.identifier
            )
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home, afi],
            people: [],
            transitTypes: [
                TransitType(canonicalName: "Bolt", aliases: ["bolt"]),
            ],
            modelContext: context
        )

        let sentence = "Bolt from Home to AFI from 12:00 to 14:00"
        model.editorText = AttributedString(sentence)
        model.editorTextDidChange()

        #expect(model.isSyntaxValid)
        #expect(model.canSubmit)
        #expect(model.draft.location(.origin)?.displayName == "Home")
        #expect(model.draft.location(.destination)?.displayName == "AFI")
        #expect(model.draft.time(.start) != nil)
        #expect(model.draft.time(.end) != nil)
    }

    @Test("Transit endpoint at times remain adjacent in either order")
    func transitEndpointAtEitherOrder() throws {
        let context = try makeContext()
        let home = Place(
            name: "Home",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: zone.identifier
            )
        )
        let afi = Place(
            name: "AFI",
            location: Location(
                latitude: 45.66,
                longitude: 25.61,
                timeZoneIdentifier: zone.identifier
            )
        )
        let model = GuidedEntryComposerModel()
        model.prepare(
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 18),
            places: [home, afi],
            people: [],
            transitTypes: [
                TransitType(canonicalName: "Bolt", aliases: ["bolt"]),
            ],
            modelContext: context
        )

        model.editorText = AttributedString(
            "Bolt to AFI at 14:00 from Home at 12:00"
        )
        model.editorTextDidChange()

        #expect(model.isSyntaxValid)
        #expect(model.canSubmit)
        #expect(model.draft.time(.start) != nil)
        #expect(model.draft.time(.end) != nil)

        model.editorText = AttributedString(
            "Bolt from Home to AFI with Emma at 12:00"
        )
        model.editorTextDidChange()
        #expect(!model.isSyntaxValid)
        #expect(!model.canSubmit)
    }

    @Test("Guided visits persist descriptions without model diagnostics")
    func guidedVisitPersistence() throws {
        let context = try makeContext()
        let cinema = Place(
            name: "Cinema",
            location: Location(
                latitude: 45.65,
                longitude: 25.60,
                timeZoneIdentifier: zone.identifier
            )
        )
        context.insert(cinema)
        let raw = "Watch The Odyssey at Cinema from 19:00 for 2 hr"
        let entry = try PlaceVisitEntryStore.insert(
            draft: ResolvedPlaceVisitDraft(
                description: "Watch The Odyssey",
                place: cinema,
                location: cinema.location,
                placeRawText: "Cinema",
                startTime: date("2026-07-18T19:00:00+03:00"),
                endTime: date("2026-07-18T21:00:00+03:00"),
                timeConfidence: .explicit,
                people: [],
                candidates: [],
                unresolvedPeople: [],
                fieldReviews: [],
                entryKindReviewReason: nil
            ),
            rawInput: raw,
            in: context
        )

        #expect(entry.placeVisitDetails?.description == "Watch The Odyssey")
        #expect(entry.rawInputString == raw)
        #expect(entry.needsReview == false)
    }

    @Test("Stay remains descriptionless and old visit data stays readable")
    func stayCompatibility() throws {
        let context = try makeContext()
        let details = PlaceVisitDetails()
        let entry = LogEntry(kind: .placeVisit, needsReview: false)
        entry.placeVisitDetails = details
        context.insert(entry)
        try context.save()

        let stored = try #require(
            context.fetch(FetchDescriptor<LogEntry>()).first
        )
        #expect(stored.placeVisitDetails?.description == nil)
    }

    @Test("Route duration cache reuses an in-flight MapKit request")
    func routeDurationCacheReusesInFlightRequest() async {
        let origin = location(
            "Origin",
            latitude: 45.65,
            longitude: 25.59
        )
        let destination = location(
            "Destination",
            latitude: 45.67,
            longitude: 25.62
        )
        var requestCount = 0
        let cache = GuidedComposerRouteDurationCache {
            _, _, _ in
            requestCount += 1
            try await Task.sleep(for: .milliseconds(20))
            return 600
        }

        async let first = cache.duration(
            from: origin,
            to: destination,
            routingMode: .automobile
        )
        async let second = cache.duration(
            from: origin,
            to: destination,
            routingMode: .automobile
        )
        let values = await [first, second]

        #expect(values == [600, 600])
        #expect(requestCount == 1)
    }

    @Test("Current location capture is intent-gated and expires")
    func currentLocationCaptureLifecycle() async throws {
        var now = date("2026-07-31T10:00:00+03:00")
        var captureCount = 0
        let captured = Location(latitude: 45.65, longitude: 25.59)
        let coordinator = GuidedComposerCurrentLocationCoordinator(
            authorizationProvider: { .authorizedWhenInUse },
            capture: {
                captureCount += 1
                return captured
            },
            clock: { now }
        )

        coordinator.update(
            isNeeded: false,
            isToday: true,
            onChange: {}
        )
        #expect(captureCount == 0)

        coordinator.update(
            isNeeded: true,
            isToday: true,
            onChange: {}
        )
        try await Task.sleep(for: .milliseconds(10))
        #expect(captureCount == 1)
        #expect(coordinator.freshLocation == captured)

        coordinator.update(
            isNeeded: true,
            isToday: true,
            onChange: {}
        )
        #expect(captureCount == 1)

        now.addTimeInterval(
            GuidedComposerPolicy.currentLocationTimeToLive + 1
        )
        coordinator.update(
            isNeeded: true,
            isToday: true,
            onChange: {}
        )
        try await Task.sleep(for: .milliseconds(10))
        #expect(captureCount == 2)
        #expect(coordinator.freshLocation == captured)
    }

    @Test("Location permission is requested only after location intent")
    func undeterminedLocationAccessWaitsForIntent() async throws {
        var captureCount = 0
        let coordinator = GuidedComposerCurrentLocationCoordinator(
            authorizationProvider: { .notDetermined },
            capture: {
                captureCount += 1
                return Location(latitude: 45.65, longitude: 25.59)
            }
        )

        coordinator.update(
            isNeeded: false,
            isToday: true,
            onChange: {}
        )
        #expect(captureCount == 0)

        coordinator.update(
            isNeeded: true,
            isToday: true,
            onChange: {}
        )
        try await Task.sleep(for: .milliseconds(10))

        #expect(captureCount == 1)
        #expect(coordinator.status == .available)
    }

    @Test("Explicit date formatters are reusable and durations localize")
    func cachedExplicitDatesAndLocalizedDurations() throws {
        let day = TimelineDayKey(year: 2026, month: 7, day: 31)
        for _ in 0..<3 {
            let parsed = GuidedComposerTimeParser.parseTime(
                "31.07.2026 14:30",
                role: .start,
                selectedDay: day,
                timeZone: zone
            )
            #expect(parsed != nil)
        }

        let english = GuidedComposerTimeParser.displayDuration(
            4_800,
            locale: Locale(identifier: "en_US")
        )
        let romanian = GuidedComposerTimeParser.displayDuration(
            4_800,
            locale: Locale(identifier: "ro_RO")
        )
        #expect(!english.isEmpty)
        #expect(!romanian.isEmpty)
    }

    private func token(
        _ text: String,
        _ value: ComposerTokenValue
    ) -> ComposerToken {
        ComposerToken(displayText: text, value: value)
    }

    private func routeRoles(
        in tokens: [ComposerToken]
    ) -> Set<ComposerValueRole> {
        Set(tokens.compactMap {
            $0.role == .connector ? nil : $0.role
        })
    }

    private func location(
        _ name: String,
        latitude: Double,
        longitude: Double,
        systemImage: PlaceSystemImage = .mappin
    ) -> ComposerLocationCandidate {
        ComposerLocationCandidate(
            id: "\(name)-\(latitude)-\(longitude)",
            displayName: name,
            location: Location(
                latitude: latitude,
                longitude: longitude,
                displayName: name,
                timeZoneIdentifier: zone.identifier
            ),
            systemImage: systemImage,
            source: .savedPlace
        )
    }

    private func visit(
        place: Place,
        start: String,
        end: String
    ) -> LogEntry {
        let entry = LogEntry(
            kind: .placeVisit,
            startTime: date(start),
            endTime: date(end),
            needsReview: false
        )
        entry.placeVisitDetails = PlaceVisitDetails(place: place)
        return entry
    }

    private func transit(
        origin: Place,
        destination: Place,
        start: String,
        end: String
    ) -> LogEntry {
        let entry = LogEntry(
            kind: .transit,
            startTime: date(start),
            endTime: date(end),
            needsReview: false
        )
        entry.transitDetails = TransitDetails(
            type: "Car",
            originPlace: origin,
            destinationPlace: destination
        )
        return entry
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            LogEntry.self,
            Person.self,
            Place.self,
            TransitDetails.self,
            PlaceVisitDetails.self,
            WorkoutDetails.self,
            TransitType.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(isStoredInMemoryOnly: true),
            ]
        )
        return ModelContext(container)
    }

    private func date(_ value: String) -> Date {
        (try? Date(value, strategy: .iso8601)) ?? .distantPast
    }
}
