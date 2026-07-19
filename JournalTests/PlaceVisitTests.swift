import Foundation
import SwiftData
import Testing

@testable import Journal

@Suite("Unified logging and place visits")
@MainActor
struct PlaceVisitTests {
    @Test("The structured envelope accepts exactly one matching payload")
    func structuredEnvelopeValidation() throws {
        let visit = generatedVisit(
            start: nil,
            end: nil,
            timeNeedsReview: true
        )
        let valid = GeneratedEntryLog(
            entryKind: .placeVisit,
            entryKindReview: review(false),
            transit: nil,
            placeVisit: visit
        )
        guard case .placeVisit = try EntryLanguageModelService.validate(valid) else {
            Issue.record("Expected a validated place-visit payload")
            return
        }

        let invalid = GeneratedEntryLog(
            entryKind: .transit,
            entryKindReview: review(false),
            transit: nil,
            placeVisit: visit
        )
        #expect(throws: EntryLanguageModelValidationError.self) {
            try EntryLanguageModelService.validate(invalid)
        }
    }

    @Test("Saved aliases and people resolve without MapKit candidates")
    func savedAliasResolution() throws {
        let place = Place(
            name: "Kasho Mosaico Urbano",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: "Europe/Bucharest"
            )
        )
        place.aliases = ["kasho"]
        let person = Person(name: "Alexandra")
        person.aliases = ["Alex"]
        let references = EntryPromptReferences(
            places: [place],
            people: [person]
        )
        let placeKey = try #require(
            references.placesByKey.first(where: { $0.value.id == place.id })?.key
        )
        let personKey = try #require(
            references.peopleByKey.first(where: { $0.value.id == person.id })?.key
        )
        let generated = GeneratedPlaceVisitLog(
            place: GeneratedLocationResolution(
                rawText: "kasho",
                selectedLocationKey: placeKey,
                alternativeLocationKeys: [],
                review: review(false)
            ),
            time: GeneratedPlaceVisitTimeResolution(
                rawText: "from 10 to 11",
                startTimeISO8601: "2026-07-17T10:00:00+03:00",
                endTimeISO8601: "2026-07-17T11:00:00+03:00",
                review: review(false)
            ),
            people: [
                GeneratedPersonResolution(
                    rawText: "Alex",
                    personKey: personKey,
                    review: review(false)
                ),
            ]
        )

        let draft = PlaceVisitResolutionService.resolve(
            generated: generated,
            entryKindReview: review(false),
            references: references,
            toolSearches: [],
            rawInput: "At kasho with Alex from 10 to 11",
            people: [person]
        )

        #expect(draft.place?.id == place.id)
        #expect(draft.people.map(\.id) == [person.id])
        #expect(draft.timeConfidence == .explicit)
        #expect(draft.needsReview == false)
    }

    @Test("Visit time preserves partial input and never invents a boundary")
    func partialAndMissingTime() {
        let place = Place(
            name: "Library",
            location: Location(latitude: 45.0, longitude: 25.0)
        )
        let references = EntryPromptReferences(places: [place], people: [])
        let key = references.placesByKey.first?.key

        let partial = resolve(
            generatedVisit(
                placeKey: key,
                rawTime: "since 09:15",
                start: "2026-07-17T09:15:00+03:00",
                end: nil,
                timeNeedsReview: true
            ),
            references: references,
            rawInput: "At the Library since 09:15"
        )
        #expect(partial.startTime != nil)
        #expect(partial.endTime == nil)
        #expect(partial.fieldReviews.contains { $0.field == .time })

        let missing = resolve(
            generatedVisit(
                placeKey: key,
                start: nil,
                end: nil,
                timeNeedsReview: true
            ),
            references: references,
            rawInput: "Lunch at Library"
        )
        #expect(missing.startTime == nil)
        #expect(missing.endTime == nil)
        #expect(missing.timeConfidence == .unresolved)
    }

    @Test("Visit time accepts useful history placements and preserves ambiguity review")
    func historyVisitTimeResolution() {
        let place = Place(
            name: "AFI Brașov",
            location: Location(latitude: 45.65, longitude: 25.61)
        )
        let references = EntryPromptReferences(places: [place], people: [])
        let key = references.placesByKey.first?.key

        let historyOnly = resolve(
            generatedVisit(
                placeKey: key,
                rawTime: nil,
                start: "2026-07-18T10:15:00+03:00",
                end: "2026-07-18T10:25:00+03:00",
                timeNeedsReview: false
            ),
            references: references,
            rawInput: "Stayed at AFI"
        )
        #expect(historyOnly.startTime == date("2026-07-18T10:15:00+03:00"))
        #expect(historyOnly.endTime == date("2026-07-18T10:25:00+03:00"))
        #expect(historyOnly.timeConfidence == .inferredFromHistory)
        #expect(historyOnly.fieldReviews.contains { $0.field == .time } == false)

        let ambiguous = resolve(
            generatedVisit(
                placeKey: key,
                rawTime: "for 10 minutes",
                start: "2026-07-18T18:20:00+03:00",
                end: "2026-07-18T18:30:00+03:00",
                timeNeedsReview: true
            ),
            references: references,
            rawInput: "Stayed at AFI for 10 minutes"
        )
        #expect(ambiguous.startTime == date("2026-07-18T18:20:00+03:00"))
        #expect(ambiguous.endTime == date("2026-07-18T18:30:00+03:00"))
        #expect(ambiguous.fieldReviews.contains { $0.field == .time })
    }

    @Test("Unknown and wrong-role candidate keys require place review")
    func candidateValidation() {
        let result = TransitMapSearchResult(
            name: "Blue Lantern",
            address: "Brașov, Romania",
            latitude: 45.65,
            longitude: 25.60,
            timeZoneIdentifier: "Europe/Bucharest",
            distanceKilometers: 1.2,
            walkingDurationMinutes: nil,
            automobileDurationMinutes: nil
        )
        let search = TransitToolSearch(
            role: .visit,
            query: "Blue Lantern",
            candidates: [
                TransitToolCandidate(
                    candidateKey: "visit-search-1-candidate-1",
                    result: result
                ),
            ]
        )
        let references = EntryPromptReferences(places: [], people: [])
        let generated = GeneratedPlaceVisitLog(
            place: GeneratedLocationResolution(
                rawText: "Blue Lantern",
                selectedLocationKey: nil,
                alternativeLocationKeys: ["visit-search-1-candidate-1"],
                review: review(true, reason: "Choose a search result.")
            ),
            time: GeneratedPlaceVisitTimeResolution(
                rawText: nil,
                startTimeISO8601: nil,
                endTimeISO8601: nil,
                review: review(true)
            ),
            people: []
        )
        let draft = resolve(
            generated,
            references: references,
            searches: [search],
            rawInput: "Dinner at Blue Lantern"
        )
        #expect(draft.candidates.count == 1)
        #expect(draft.place == nil)
        #expect(draft.fieldReviews.contains { $0.field == .place })

        let unknown = GeneratedPlaceVisitLog(
            place: GeneratedLocationResolution(
                rawText: "Blue Lantern",
                selectedLocationKey: nil,
                alternativeLocationKeys: ["origin-search-1-candidate-1"],
                review: review(false)
            ),
            time: generated.time,
            people: []
        )
        let unknownDraft = resolve(
            unknown,
            references: references,
            searches: [search],
            rawInput: "Dinner at Blue Lantern"
        )
        #expect(unknownDraft.candidates.isEmpty)
        #expect(unknownDraft.fieldReviews.contains { $0.field == .place })
    }

    @Test("A confident MapKit result is a valid unsaved visit location")
    func confidentSearchLocation() {
        let result = TransitMapSearchResult(
            name: "Blue Lantern",
            address: "Brașov, Romania",
            latitude: 45.65,
            longitude: 25.60,
            timeZoneIdentifier: "Europe/Bucharest",
            distanceKilometers: 1.2,
            walkingDurationMinutes: nil,
            automobileDurationMinutes: nil
        )
        let search = TransitToolSearch(
            role: .visit,
            query: "Blue Lantern",
            candidates: [
                TransitToolCandidate(
                    candidateKey: "visit-search-1-candidate-1",
                    result: result
                ),
            ]
        )
        let generated = GeneratedPlaceVisitLog(
            place: GeneratedLocationResolution(
                rawText: "Blue Lantern",
                selectedLocationKey: "visit-search-1-candidate-1",
                alternativeLocationKeys: [],
                review: review(false)
            ),
            time: GeneratedPlaceVisitTimeResolution(
                rawText: "from 19 to 21",
                startTimeISO8601: "2026-07-18T19:00:00+03:00",
                endTimeISO8601: "2026-07-18T21:00:00+03:00",
                review: review(false)
            ),
            people: []
        )

        let draft = resolve(
            generated,
            references: EntryPromptReferences(places: [], people: []),
            searches: [search],
            rawInput: "Dinner at Blue Lantern from 19 to 21"
        )

        #expect(draft.place == nil)
        #expect(draft.location?.displayName == "Blue Lantern")
        #expect(draft.location?.timeZoneIdentifier == "Europe/Bucharest")
        #expect(draft.fieldReviews.contains { $0.field == .place } == false)
    }

    @Test("Malformed and inverted visit timestamps require time review")
    func invalidTimeValidation() {
        let place = Place(
            name: "Home",
            location: Location(latitude: 45, longitude: 25)
        )
        let references = EntryPromptReferences(places: [place], people: [])
        let key = references.placesByKey.first?.key

        let malformed = resolve(
            generatedVisit(
                placeKey: key,
                rawTime: "from ten to eleven",
                start: "not-a-date",
                end: "2026-07-17T11:00:00+03:00",
                timeNeedsReview: false
            ),
            references: references,
            rawInput: "At Home from ten to eleven"
        )
        #expect(malformed.fieldReviews.contains { $0.field == .time })

        let inverted = resolve(
            generatedVisit(
                placeKey: key,
                rawTime: "from 12 to 10",
                start: "2026-07-17T12:00:00+03:00",
                end: "2026-07-17T10:00:00+03:00",
                timeNeedsReview: false
            ),
            references: references,
            rawInput: "At Home from 12 to 10"
        )
        #expect(inverted.fieldReviews.contains { $0.field == .time })
    }

    @Test("Visit storage snapshots timezone and model exchange")
    func visitStorage() throws {
        let context = try makeContext()
        let place = Place(
            name: "Kasho",
            location: Location(
                latitude: 45.65,
                longitude: 25.59,
                timeZoneIdentifier: "Europe/Bucharest"
            )
        )
        context.insert(place)
        let draft = ResolvedPlaceVisitDraft(
            place: place,
            placeRawText: "kasho",
            startTime: date("2026-07-17T10:00:00+03:00"),
            endTime: date("2026-07-17T11:00:00+03:00"),
            timeConfidence: .explicit,
            people: [],
            candidates: [],
            unresolvedPeople: [],
            fieldReviews: [],
            entryKindReviewReason: nil
        )
        let entry = try PlaceVisitEntryStore.insert(
            draft: draft,
            rawInput: "At kasho from 10 to 11",
            modelExchange: EntryModelExchange(
                instructions: "instructions",
                prompt: "prompt",
                toolTranscript: "tools",
                response: "response"
            ),
            in: context
        )

        #expect(entry.kind == .placeVisit)
        #expect(entry.startTimeZoneIdentifier == "Europe/Bucharest")
        #expect(entry.endTimeZoneIdentifier == "Europe/Bucharest")
        #expect(entry.modelPrompt == "prompt")
        #expect(entry.modelToolTranscript == "tools")
    }

    @Test("Derived statistics follow edits, conversion review, and deletion")
    func derivedStatistics() {
        let firstPlace = Place(
            name: "First",
            location: Location(latitude: 45, longitude: 25)
        )
        let secondPlace = Place(
            name: "Second",
            location: Location(latitude: 46, longitude: 26)
        )
        let first = visitEntry(
            place: firstPlace,
            start: date("2026-07-16T10:00:00Z"),
            end: date("2026-07-16T11:00:00Z")
        )
        let second = visitEntry(
            place: firstPlace,
            start: nil,
            end: nil
        )

        var statistics = PlaceVisitStatisticsService.calculate(
            from: [first, second]
        )
        #expect(statistics[firstPlace.id]?.visitCount == 2)
        #expect(statistics[firstPlace.id]?.lastVisitedAt == first.endTime)

        second.placeVisitDetails?.place = secondPlace
        statistics = PlaceVisitStatisticsService.calculate(from: [first, second])
        #expect(statistics[firstPlace.id]?.visitCount == 1)
        #expect(statistics[secondPlace.id]?.visitCount == 1)

        second.entryKindReviewReason = "Ambiguous"
        statistics = PlaceVisitStatisticsService.calculate(from: [first, second])
        #expect(statistics[secondPlace.id] == nil)
        statistics = PlaceVisitStatisticsService.calculate(from: [second])
        #expect(statistics[firstPlace.id] == nil)
    }

    @Test("Place visits use the existing multi-day timeline projection")
    func visitTimelineProjection() {
        let snapshot = TimelineEntrySnapshot(
            createdAt: date("2026-07-17T08:00:00+03:00"),
            startTime: date("2026-07-17T22:00:00+03:00"),
            endTime: date("2026-07-18T02:00:00+03:00"),
            startTimeZoneIdentifier: "Europe/Bucharest",
            endTimeZoneIdentifier: "Europe/Bucharest",
            creationTimeZoneIdentifier: "Europe/Bucharest",
            timeConfidence: .explicit,
            kind: .placeVisit,
            visitPlace: "Home",
            visitSystemImage: .house
        )
        let first = TimelineProjection.project(
            entries: [snapshot],
            for: TimelineDayKey(year: 2026, month: 7, day: 17)
        )
        let second = TimelineProjection.project(
            entries: [snapshot],
            for: TimelineDayKey(year: 2026, month: 7, day: 18)
        )
        #expect(first.occurrences.first?.kind == .placeVisit)
        #expect(first.occurrences.first?.visitPlace == "Home")
        #expect(second.occurrences.count == 1)
    }

    @Test("Entry-kind conversion preserves shared entry metadata in both directions")
    func entryKindConversion() throws {
        let context = try makeContext()
        let origin = Place(
            name: "Home",
            location: Location(latitude: 45.65, longitude: 25.60)
        )
        let destination = Place(
            name: "Kasho",
            location: Location(latitude: 45.66, longitude: 25.59)
        )
        let person = Person(name: "Alex")
        let entry = visitEntry(
            place: destination,
            start: date("2026-07-17T10:00:00+03:00"),
            end: date("2026-07-17T11:00:00+03:00")
        )
        entry.rawInputString = "Ambiguous input"
        entry.modelResponse = "exact response"
        entry.photoReferences = [
            PhotoReference(assetLocalIdentifier: "asset"),
        ]
        entry.people = [person]
        entry.entryKindReviewReason = "Could be transit."
        entry.needsReview = true
        context.insert(origin)
        context.insert(destination)
        context.insert(person)
        context.insert(entry)
        try context.save()

        let toTransit = EntryKindConversionModel(
            entry: entry,
            targetKind: .transit
        )
        toTransit.transitType = "Walk"
        toTransit.originPlaceID = origin.id
        toTransit.destinationPlaceID = destination.id
        #expect(
            toTransit.save(
                entry: entry,
                places: [origin, destination],
                people: [person],
                in: context
            )
        )
        #expect(entry.kind == .transit)
        #expect(entry.transitDetails?.destinationPlace?.id == destination.id)
        #expect(entry.placeVisitDetails == nil)
        #expect(entry.rawInputString == "Ambiguous input")
        #expect(entry.modelResponse == "exact response")
        #expect(entry.photoReferences.first?.assetLocalIdentifier == "asset")

        let toVisit = EntryKindConversionModel(
            entry: entry,
            targetKind: .placeVisit
        )
        #expect(
            toVisit.save(
                entry: entry,
                places: [origin, destination],
                people: [person],
                in: context
            )
        )
        #expect(entry.kind == .placeVisit)
        #expect(entry.placeVisitDetails?.place?.id == destination.id)
        #expect(entry.transitDetails == nil)
        #expect(entry.people.map(\.id) == [person.id])
    }

    @Test("The prompt summarizes confirmed entries on the selected day")
    func selectedDayHistoryPrompt() {
        let afi = Place(
            name: "AFI Brașov",
            location: Location(
                latitude: 45.65,
                longitude: 25.61,
                formattedAddress: "AFI Brașov, Romania",
                timeZoneIdentifier: "Europe/Bucharest"
            )
        )
        afi.aliases = ["afi"]
        let visit = visitEntry(
            place: afi,
            start: date("2026-07-18T10:30:00+03:00"),
            end: date("2026-07-18T11:00:00+03:00")
        )
        visit.startTimeZoneIdentifier = "Europe/Bucharest"
        visit.endTimeZoneIdentifier = "Europe/Bucharest"
        visit.timeConfidence = .explicit
        let selectedDay = TimelineDayKey(year: 2026, month: 7, day: 18)
        let references = EntryPromptReferences(
            places: [afi],
            people: [],
            historyEntries: [visit],
            selectedDay: selectedDay
        )
        let context = EntryPromptContext(
            places: [afi],
            people: [],
            transitTypes: [],
            visitStatisticsByPlaceID: [:],
            selectedDay: selectedDay,
            selectedDayEntries: [visit],
            currentDate: date("2026-07-18T12:00:00+03:00"),
            currentLocation: Location(
                latitude: 45.66,
                longitude: 25.60,
                formattedAddress: "Brașov, Romania",
                timeZoneIdentifier: "Europe/Bucharest"
            )
        )

        let prompt = EntryLanguageModelService.prompt(
            input: "Walk home from afi",
            context: context,
            references: references
        )

        #expect(prompt.contains(#""selectedDayHistory""#))
        #expect(prompt.contains(#""mode" : "today""#))
        #expect(
            prompt.contains(
                #""entryTimestampISO8601" : "2026-07-18T12:00:00+03:00""#
            )
        )
        #expect(prompt.contains(#""entryLocalDate""#) == false)
        #expect(prompt.contains(#""selectedLocalDate""#) == false)
        #expect(prompt.contains(#""savedPlaceKey" : "afi-brasov""#))
        #expect(prompt.contains(#""relativeDay" : "selectedDay""#))
        #expect(prompt.contains("history-selected-day-entry-1-visit-location"))
        #expect(prompt.contains(#""startTimeISO8601" : "2026-07-18T10:30:00+03:00""#))
        #expect(prompt.contains(#""endTimeISO8601" : "2026-07-18T11:00:00+03:00""#))
    }

    @Test("A non-today selected date replaces the current timestamp")
    func selectedDatePromptContext() {
        let currentLocation = Location(
            latitude: 45.66,
            longitude: 25.60,
            formattedAddress: "Brașov, Romania",
            timeZoneIdentifier: "Europe/Bucharest"
        )
        let context = EntryPromptContext(
            places: [],
            people: [],
            transitTypes: [],
            visitStatisticsByPlaceID: [:],
            selectedDay: TimelineDayKey(year: 2026, month: 7, day: 12),
            selectedDayEntries: [],
            currentDate: date("2026-07-19T12:00:00+03:00"),
            currentLocation: currentLocation
        )

        let prompt = EntryLanguageModelService.prompt(
            input: "Coffee at 10",
            context: context,
            references: EntryPromptReferences(places: [], people: [])
        )

        #expect(prompt.contains("ENTRY DATE CONTEXT — AUTHORITATIVE"))
        #expect(prompt.contains(#""mode" : "selectedDate""#))
        #expect(prompt.contains(#""entryLocalDate" : "2026-07-12""#))
        #expect(prompt.contains(#""entryTimestampISO8601""#) == false)
        #expect(prompt.contains("2026-07-19T12:00:00+03:00") == false)
    }

    @Test("Instructions use selected-day history for flexible visit placement")
    func visitHistoryInstructions() {
        let instructions = EntryLanguageModelService.instructions

        #expect(instructions.contains("Entries do not need"))
        #expect(instructions.contains("to be adjacent"))
        #expect(instructions.contains("stayed at AFI for 10 minutes"))
        #expect(instructions.contains("after the Bolt from Home"))
        #expect(instructions.contains("still return its complete timestamps"))
        #expect(instructions.contains("workout's origin after it"))
        #expect(instructions.contains("does not require the user to save it"))
        #expect(instructions.contains("Never infer a place-visit time from history") == false)
    }

    @Test("Unsaved workout endpoints receive reusable history location keys")
    func unsavedWorkoutHistoryLocationKey() throws {
        let origin = Location(
            latitude: 44.446,
            longitude: 26.074,
            displayName: "Piața Revoluției",
            formattedAddress: "Piața Revoluției, Bucharest, Romania",
            timeZoneIdentifier: "Europe/Bucharest"
        )
        let destination = Location(
            latitude: 44.45,
            longitude: 26.09,
            displayName: "University Square",
            formattedAddress: "University Square, Bucharest, Romania",
            timeZoneIdentifier: "Europe/Bucharest"
        )
        let workout = LogEntry(
            kind: .workout,
            startTime: date("2026-07-18T09:10:00+03:00"),
            endTime: date("2026-07-18T09:40:00+03:00"),
            needsReview: false
        )
        workout.workoutDetails = WorkoutDetails(
            healthKitWorkoutUUID: UUID(),
            activityTypeRawValue: 52,
            activityName: "Walk",
            movementKind: .moving,
            originLocation: origin,
            destinationLocation: destination
        )
        let selectedDay = TimelineDayKey(year: 2026, month: 7, day: 18)
        let references = EntryPromptReferences(
            places: [],
            people: [],
            historyEntries: [workout],
            selectedDay: selectedDay
        )
        let key = try #require(
            references.historyLocationKey(
                entryID: workout.id,
                role: "workout-origin"
            )
        )

        #expect(key == "history-selected-day-entry-1-workout-origin")
        #expect(references.locationsByKey[key]?.location == origin)
        #expect(references.locationsByKey[key]?.place == nil)
    }

    @Test("Saving a location as a place links selected snapshots without rewriting them")
    func savedPlacePromotion() throws {
        let context = try makeContext()
        let snapshot = Location(
            latitude: 45.6501,
            longitude: 25.6001,
            displayName: "Coffee Shop",
            formattedAddress: "1 Main Street, Brașov",
            timeZoneIdentifier: "Europe/Bucharest"
        )
        let entry = LogEntry(
            kind: .placeVisit,
            startTime: date("2026-07-18T10:00:00+03:00"),
            endTime: date("2026-07-18T11:00:00+03:00"),
            needsReview: false
        )
        entry.placeVisitDetails = PlaceVisitDetails(
            location: snapshot,
            placeRawText: "coffee shop"
        )
        let place = Place(
            name: "Coffee Shop",
            location: Location(
                latitude: 45.6502,
                longitude: 25.6002,
                displayName: "Coffee Shop",
                formattedAddress: "1 Main Street, Brașov",
                timeZoneIdentifier: "Europe/Bucharest"
            )
        )
        context.insert(entry)
        context.insert(place)
        try context.save()

        let matches = try SavedPlacePromotionService.matches(
            for: place,
            in: context
        )
        #expect(matches.count == 1)
        try SavedPlacePromotionService.apply(matches, to: place, in: context)

        #expect(entry.placeVisitDetails?.place?.id == place.id)
        #expect(entry.placeVisitDetails?.location == snapshot)
    }

    @Test("A confirmed visit boundary validates transit history inference")
    func historyTimeInference() throws {
        let afi = Place(
            name: "AFI Brașov",
            location: Location(latitude: 45.65, longitude: 25.61)
        )
        let home = Place(
            name: "Home",
            location: Location(latitude: 45.66, longitude: 25.60)
        )
        let historyVisit = visitEntry(
            place: afi,
            start: date("2026-07-18T10:30:00+03:00"),
            end: date("2026-07-18T11:00:00+03:00")
        )
        historyVisit.timeConfidence = .explicit
        let references = EntryPromptReferences(
            places: [afi, home],
            people: []
        )
        let afiKey = try #require(
            references.placesByKey.first { $0.value.id == afi.id }?.key
        )
        let homeKey = try #require(
            references.placesByKey.first { $0.value.id == home.id }?.key
        )
        let walk = TransitType(
            canonicalName: "Walk",
            aliases: ["walking"],
            routingMode: .walking
        )
        let generated = GeneratedTransitLog(
            transitType: GeneratedTransitTypeResolution(
                rawText: "Walk",
                canonicalName: "Walk",
                review: review(false)
            ),
            origin: GeneratedLocationResolution(
                rawText: "afi",
                selectedLocationKey: afiKey,
                alternativeLocationKeys: [],
                review: review(false)
            ),
            destination: GeneratedLocationResolution(
                rawText: "home",
                selectedLocationKey: homeKey,
                alternativeLocationKeys: [],
                review: review(false)
            ),
            time: GeneratedTimeResolution(
                rawText: nil,
                resolutionKind: .inferredFromHistory,
                startTimeISO8601: "2026-07-18T11:00:00+03:00",
                endTimeISO8601: "2026-07-18T11:14:00+03:00",
                durationSource: .mapkitWalking,
                review: review(false)
            ),
            people: []
        )

        let draft = TransitResolutionService.resolve(
            generated: generated,
            references: references,
            toolSearches: [],
            rawInput: "Walk home from afi",
            people: [],
            transitTypes: [walk],
            currentLocation: Location(latitude: 44, longitude: 26),
            now: date("2026-07-18T15:00:00+03:00"),
            selectedDayEntries: [historyVisit]
        )

        #expect(draft.timeConfidence == .inferredFromHistory)
        #expect(draft.startTime == historyVisit.endTime)
        #expect(draft.fieldReviews.contains { $0.field == .time } == false)
    }

    private func generatedVisit(
        placeKey: String? = nil,
        rawTime: String? = nil,
        start: String?,
        end: String?,
        timeNeedsReview: Bool
    ) -> GeneratedPlaceVisitLog {
        GeneratedPlaceVisitLog(
            place: GeneratedLocationResolution(
                rawText: "place",
                selectedLocationKey: placeKey,
                alternativeLocationKeys: [],
                review: review(placeKey == nil)
            ),
            time: GeneratedPlaceVisitTimeResolution(
                rawText: rawTime,
                startTimeISO8601: start,
                endTimeISO8601: end,
                review: review(timeNeedsReview)
            ),
            people: []
        )
    }

    private func resolve(
        _ generated: GeneratedPlaceVisitLog,
        references: EntryPromptReferences,
        searches: [TransitToolSearch] = [],
        rawInput: String
    ) -> ResolvedPlaceVisitDraft {
        PlaceVisitResolutionService.resolve(
            generated: generated,
            entryKindReview: review(false),
            references: references,
            toolSearches: searches,
            rawInput: rawInput,
            people: Array(references.peopleByKey.values)
        )
    }

    private func review(
        _ needsReview: Bool,
        reason: String? = nil
    ) -> GeneratedFieldReview {
        GeneratedFieldReview(
            needsReview: needsReview,
            reason: reason ?? (needsReview ? "Needs review." : nil)
        )
    }

    private func visitEntry(
        place: Place,
        start: Date?,
        end: Date?
    ) -> LogEntry {
        let entry = LogEntry(
            kind: .placeVisit,
            startTime: start,
            endTime: end,
            needsReview: start == nil || end == nil
        )
        entry.placeVisitDetails = PlaceVisitDetails(place: place)
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
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func date(_ value: String) -> Date {
        (try? Date(value, strategy: .iso8601)) ?? .distantPast
    }
}
