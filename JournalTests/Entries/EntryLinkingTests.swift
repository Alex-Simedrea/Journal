import Foundation
import SwiftData
import Testing

@testable import Journal

@Suite("Entry boundary linking")
@MainActor
struct EntryLinkingTests {
  @Test("Existing adjacent entries are linked retroactively")
  func retroactiveReconciliation() throws {
    let context = try makeContext()
    let home = place("Home", latitude: 45.65)
    let cafe = place("Cafe", latitude: 45.66)
    let visit = visit(home, start: 1_000, end: 2_000)
    let transit = transit(
      from: home,
      to: cafe,
      start: 2_000,
      end: 3_000
    )
    [home, cafe].forEach(context.insert)
    [visit, transit].forEach(context.insert)
    try context.save()

    #expect(try EntryLinkingService.reconcile(in: context))
    try context.save()

    #expect(visit.linkedNextEntryID == transit.id)
    #expect(transit.linkedPreviousEntryID == visit.id)
  }

  @Test("Explicit unlink is preserved during later reconciliation")
  func unlinkSuppression() throws {
    let context = try makeContext()
    let home = place("Home", latitude: 45.65)
    let cafe = place("Cafe", latitude: 45.66)
    let visit = visit(home, start: 1_000, end: 2_000)
    let transit = transit(
      from: home,
      to: cafe,
      start: 2_000,
      end: 3_000
    )
    [home, cafe].forEach(context.insert)
    [visit, transit].forEach(context.insert)
    try context.save()
    _ = try EntryLinkingService.reconcile(in: context)

    try EntryLinkingService.unlink(visit, from: transit, in: context)
    _ = try EntryLinkingService.reconcile(in: context)

    #expect(visit.linkedNextEntryID == nil)
    #expect(transit.linkedPreviousEntryID == nil)
    #expect(visit.suppressedNextEntryID == transit.id)
    #expect(transit.suppressedPreviousEntryID == visit.id)
  }

  @Test("Editing linked time updates the other side of the boundary")
  func linkedTimePropagation() throws {
    let context = try makeContext()
    let home = place("Home", latitude: 45.65)
    let cafe = place("Cafe", latitude: 45.66)
    let visit = visit(home, start: 1_000, end: 2_000)
    let transit = transit(
      from: home,
      to: cafe,
      start: 2_000,
      end: 3_000
    )
    [home, cafe].forEach(context.insert)
    [visit, transit].forEach(context.insert)
    try context.save()
    _ = try EntryLinkingService.reconcile(in: context)

    let session = EntryDetailEditSession(entry: transit)
    session.startTime = Date(timeIntervalSince1970: 2_200)
    try EntryDetailEditingService.saveTime(
      entry: transit,
      session: session,
      in: context
    )

    #expect(visit.endTime == Date(timeIntervalSince1970: 2_200))
    #expect(transit.startTime == visit.endTime)
  }

  @Test("Manual linking can match both boundary fields to the current entry")
  func manualBoundaryAlignment() throws {
    let context = try makeContext()
    let home = place("Home", latitude: 45.65)
    let work = place("Work", latitude: 45.70)
    let cafe = place("Cafe", latitude: 45.75)
    let visit = visit(home, start: 1_000, end: 2_000)
    let transit = transit(
      from: work,
      to: cafe,
      start: 2_500,
      end: 3_500
    )
    [home, work, cafe].forEach(context.insert)
    [visit, transit].forEach(context.insert)
    try context.save()

    try EntryLinkingService.link(
      visit,
      to: transit,
      alignment: EntryLinkAlignment(
        timeSource: .current,
        placeSource: .current
      ),
      in: context
    )

    #expect(transit.startTime == visit.endTime)
    #expect(transit.transitDetails?.originPlace?.id == home.id)
    #expect(visit.linkedNextEntryID == transit.id)
    #expect(transit.linkedPreviousEntryID == visit.id)
  }

  @Test("Timeline-derived composer suggestions advertise automatic linking")
  func composerLinkBadge() {
    let candidate = ComposerLocationCandidate(
      id: "timeline-home",
      displayName: "Home",
      location: Location(latitude: 45.65, longitude: 25.60),
      source: .timeline
    )
    let suggestion = ComposerSuggestion(
      id: "home",
      title: "Home",
      subtitle: nil,
      systemImage: "house",
      kind: .value(
        tokens: [
          ComposerToken(
            displayText: "Home",
            value: .location(candidate, .origin)
          )
        ],
        nextSlot: .connector
      ),
      score: 1
    )

    #expect(suggestion.referencesTimelineBoundary)
  }

  @Test("Workout adjacency uses its associated place instead of recorded coordinates")
  func workoutAdjacencyUsesSavedPlace() throws {
    let context = try makeContext()
    let home = place("Home", latitude: 45.65)
    let coordinateTwin = place("Coordinate twin", latitude: 45.65)
    let visit = visit(home, start: 1_000, end: 2_000)
    let workout = workout(
      place: coordinateTwin,
      sourceLocation: home.location,
      start: 2_000,
      end: 3_000
    )
    [home, coordinateTwin].forEach(context.insert)
    [visit, workout].forEach(context.insert)
    try context.save()

    #expect(!EntryLinkingService.boundariesMatch(previous: visit, next: workout))
    #expect(!(try EntryLinkingService.reconcile(in: context)))
    #expect(visit.linkedNextEntryID == nil)

    workout.workoutDetails?.place = home
    #expect(EntryLinkingService.boundariesMatch(previous: visit, next: workout))

    let unsavedVisit = LogEntry(
      kind: .placeVisit,
      startTime: Date(timeIntervalSince1970: 1_000),
      endTime: Date(timeIntervalSince1970: 2_000),
      needsReview: false
    )
    unsavedVisit.placeVisitDetails = PlaceVisitDetails(location: home.location)
    #expect(
      EntryLinkingService.boundariesMatch(
        previous: unsavedVisit,
        next: workout
      )
    )

    #expect(try EntryLinkingService.reconcile(in: context))
    #expect(visit.linkedNextEntryID == workout.id)
  }

  @Test("Editing a linked neighbor never changes workout time")
  func workoutTimeIsImmutableThroughLinks() throws {
    let context = try makeContext()
    let home = place("Home", latitude: 45.65)
    let visit = visit(home, start: 1_000, end: 2_000)
    let workout = workout(
      place: home,
      sourceLocation: home.location,
      start: 2_000,
      end: 3_000
    )
    context.insert(home)
    [visit, workout].forEach(context.insert)
    try context.save()
    _ = try EntryLinkingService.reconcile(in: context)

    let originalWorkoutStart = workout.startTime
    visit.endTime = Date(timeIntervalSince1970: 2_200)
    try EntryLinkingService.propagateTimeEdit(from: visit, in: context)

    #expect(workout.startTime == originalWorkoutStart)
    #expect(visit.linkedNextEntryID == nil)
    #expect(workout.linkedPreviousEntryID == nil)
  }

  @Test("Linked place edits update only a workout's associated place")
  func workoutLinkOnlyUpdatesAssociatedPlace() throws {
    let context = try makeContext()
    let home = place("Home", latitude: 45.65)
    let gym = place("Gym", latitude: 45.70)
    let recordedCoordinate = Location(latitude: 45.651, longitude: 25.601)
    let visit = visit(home, start: 1_000, end: 2_000)
    let workout = workout(
      place: home,
      sourceLocation: recordedCoordinate,
      start: 2_000,
      end: 3_000
    )
    [home, gym].forEach(context.insert)
    [visit, workout].forEach(context.insert)
    try context.save()
    _ = try EntryLinkingService.reconcile(in: context)

    visit.placeVisitDetails?.place = gym
    visit.placeVisitDetails?.location = gym.location
    try EntryLinkingService.propagateLocationEdit(
      from: visit,
      role: .place,
      in: context
    )

    #expect(workout.workoutDetails?.place?.id == gym.id)
    #expect(workout.workoutDetails?.sourceLocation == recordedCoordinate)
    #expect(workout.startTime == Date(timeIntervalSince1970: 2_000))
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

  private func place(_ name: String, latitude: Double) -> Place {
    Place(
      name: name,
      location: Location(latitude: latitude, longitude: 25.60)
    )
  }

  private func visit(
    _ place: Place,
    start: TimeInterval,
    end: TimeInterval
  ) -> LogEntry {
    let entry = LogEntry(
      kind: .placeVisit,
      startTime: Date(timeIntervalSince1970: start),
      endTime: Date(timeIntervalSince1970: end),
      needsReview: false
    )
    entry.placeVisitDetails = PlaceVisitDetails(place: place)
    return entry
  }

  private func transit(
    from origin: Place,
    to destination: Place,
    start: TimeInterval,
    end: TimeInterval
  ) -> LogEntry {
    let entry = LogEntry(
      kind: .transit,
      startTime: Date(timeIntervalSince1970: start),
      endTime: Date(timeIntervalSince1970: end),
      needsReview: false
    )
    entry.transitDetails = TransitDetails(
      type: "Car",
      originPlace: origin,
      destinationPlace: destination
    )
    return entry
  }

  private func workout(
    place: Place,
    sourceLocation: Location,
    start: TimeInterval,
    end: TimeInterval
  ) -> LogEntry {
    let entry = LogEntry(
      kind: .workout,
      startTime: Date(timeIntervalSince1970: start),
      endTime: Date(timeIntervalSince1970: end),
      needsReview: false
    )
    entry.workoutDetails = WorkoutDetails(
      healthKitWorkoutUUID: UUID(),
      activityTypeRawValue: WorkoutActivityCatalog.runningRawValue,
      activityName: "Running",
      movementKind: .staticWorkout,
      sourceLocation: sourceLocation,
      place: place
    )
    return entry
  }
}
