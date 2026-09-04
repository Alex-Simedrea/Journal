import Foundation
import SwiftData

nonisolated enum EntryBoundarySide: String, Hashable, Sendable {
  case start
  case end
}

nonisolated enum EntryLinkValueSource: String, CaseIterable, Identifiable, Sendable {
  case current
  case neighbor

  var id: String { rawValue }
}

nonisolated struct EntryBoundaryValue: Equatable, Sendable {
  let time: Date
  let timeZoneIdentifier: String
  let placeID: UUID?
  let location: Location
  let name: String
  let systemImage: PlaceSystemImage
}

nonisolated struct EntryLinkAlignment: Equatable, Sendable {
  var timeSource: EntryLinkValueSource
  var placeSource: EntryLinkValueSource
}

nonisolated enum EntryLinkingError: LocalizedError {
  case missingBoundary
  case invalidTimeRange
  case immutableWorkoutTimes

  var errorDescription: String? {
    switch self {
    case .missingBoundary:
      String(localized: "Both entries need a time and place before they can be linked.")
    case .invalidTimeRange:
      String(localized: "That boundary would make one of the entries end before it starts.")
    case .immutableWorkoutTimes:
      String(localized: "Two workouts with different times can’t be linked because workout times can’t be changed.")
    }
  }
}

/// Owns entry-boundary identity, automatic backfilling, and edit propagation.
/// Keeping this logic out of the views also makes links work for imported and
/// review entries that are created without using the composer.
nonisolated enum EntryLinkingService {
  static func ordered(_ entries: [LogEntry]) -> [LogEntry] {
    entries.sorted {
      let lhs = $0.startTime ?? $0.endTime ?? $0.createdAt
      let rhs = $1.startTime ?? $1.endTime ?? $1.createdAt
      if lhs == rhs { return $0.id.uuidString < $1.id.uuidString }
      return lhs < rhs
    }
  }

  static func neighbors(
    of entry: LogEntry,
    in entries: [LogEntry]
  ) -> (previous: LogEntry?, next: LogEntry?) {
    let values = ordered(entries.filter { $0.id != entry.id } + [entry])
    guard let index = values.firstIndex(where: { $0.id == entry.id }) else {
      return (nil, nil)
    }
    return (
      index > values.startIndex ? values[index - 1] : nil,
      index + 1 < values.endIndex ? values[index + 1] : nil
    )
  }

  @discardableResult
  static func reconcile(in modelContext: ModelContext) throws -> Bool {
    let entries = ordered(try modelContext.fetch(FetchDescriptor<LogEntry>()))
    var changed = repairDanglingLinks(in: entries)
    changed = repairInvalidLinks(in: entries) || changed
    guard entries.count > 1 else { return changed }

    for index in entries.indices.dropLast() {
      let previous = entries[index]
      let next = entries[index + 1]
      guard previous.linkedNextEntryID == nil,
        next.linkedPreviousEntryID == nil,
        previous.suppressedNextEntryID != next.id,
        next.suppressedPreviousEntryID != previous.id,
        boundariesMatch(previous: previous, next: next)
      else {
        continue
      }
      setLinked(previous: previous, next: next)
      changed = true
    }
    return changed
  }

  static func reconcileAndSave(in modelContext: ModelContext) throws {
    if try reconcile(in: modelContext) {
      try modelContext.save()
    }
  }

  /// Completes the reciprocal half of links declared by a detached review
  /// draft after that draft has been inserted into SwiftData.
  static func finalizeDeclaredLinks(
    for entry: LogEntry,
    in modelContext: ModelContext
  ) throws {
    let entries = try entriesByID(in: modelContext)
    let declaredIDs = [entry.linkedPreviousEntryID, entry.linkedNextEntryID]
      .compactMap { $0 }
    for id in declaredIDs {
      guard let neighbor = entries[id],
        canLink(entry, to: neighbor)
      else { continue }
      try link(
        entry,
        to: neighbor,
        in: modelContext,
        persist: false
      )
    }
  }

  static func canLink(_ entry: LogEntry, to neighbor: LogEntry) -> Bool {
    guard entry.id != neighbor.id else { return false }
    let pair = chronologicalPair(entry, neighbor)
    guard let previous = boundary(of: pair.previous, side: .end),
      let next = boundary(of: pair.next, side: .start)
    else { return false }
    if pair.previous.kind == .workout,
      pair.next.kind == .workout,
      previous.time != next.time
    {
      return false
    }
    return workoutBoundaryHasSavedPlace(pair.previous, previous)
      && workoutBoundaryHasSavedPlace(pair.next, next)
  }

  static func boundarySides(
    for entry: LogEntry,
    and neighbor: LogEntry
  ) -> (entry: EntryBoundarySide, neighbor: EntryBoundarySide) {
    let pair = chronologicalPair(entry, neighbor)
    return pair.previous.id == entry.id ? (.end, .start) : (.start, .end)
  }

  static func isLinked(_ entry: LogEntry, to neighbor: LogEntry) -> Bool {
    entry.linkedPreviousEntryID == neighbor.id
      || entry.linkedNextEntryID == neighbor.id
  }

  static func boundariesMatch(previous: LogEntry, next: LogEntry) -> Bool {
    guard let lhs = boundary(of: previous, side: .end),
      let rhs = boundary(of: next, side: .start)
    else { return false }
    return lhs.time == rhs.time
      && locationsMatch(lhs, rhs)
  }

  static func boundaryPlacesMatch(_ entry: LogEntry, _ neighbor: LogEntry) -> Bool {
    let sides = boundarySides(for: entry, and: neighbor)
    guard let lhs = boundary(of: entry, side: sides.entry),
      let rhs = boundary(of: neighbor, side: sides.neighbor)
    else { return false }
    return locationsMatch(lhs, rhs)
  }

  static func link(
    _ entry: LogEntry,
    to neighbor: LogEntry,
    alignment: EntryLinkAlignment? = nil,
    in modelContext: ModelContext,
    persist: Bool = true
  ) throws {
    let pair = chronologicalPair(entry, neighbor)
    guard let previousBoundary = boundary(of: pair.previous, side: .end),
      let nextBoundary = boundary(of: pair.next, side: .start)
    else {
      throw EntryLinkingError.missingBoundary
    }

    if !boundariesMatch(previous: pair.previous, next: pair.next) {
      let alignment =
        alignment
        ?? EntryLinkAlignment(
          timeSource: pair.previous.id == entry.id ? .current : .neighbor,
          placeSource: pair.previous.id == entry.id ? .current : .neighbor
        )
      let time: EntryBoundaryValue
      if pair.previous.kind == .workout && pair.next.kind == .workout {
        guard previousBoundary.time == nextBoundary.time else {
          throw EntryLinkingError.immutableWorkoutTimes
        }
        time = previousBoundary
      } else if pair.previous.kind == .workout {
        time = previousBoundary
      } else if pair.next.kind == .workout {
        time = nextBoundary
      } else {
        time = selectedValue(
          alignment.timeSource,
          currentIsPrevious: pair.previous.id == entry.id,
          previous: previousBoundary,
          next: nextBoundary
        )
      }
      let place = selectedValue(
        alignment.placeSource,
        currentIsPrevious: pair.previous.id == entry.id,
        previous: previousBoundary,
        next: nextBoundary
      )
      guard (pair.previous.kind == .workout
          || time.time > (pair.previous.startTime ?? .distantPast)),
        (pair.next.kind == .workout
          || time.time < (pair.next.endTime ?? .distantFuture))
      else {
        throw EntryLinkingError.invalidTimeRange
      }
      if (pair.previous.kind == .workout || pair.next.kind == .workout),
        place.placeID == nil
      {
        throw EntryLinkingError.missingBoundary
      }
      setTimeBoundary(pair.previous, side: .end, from: time)
      setTimeBoundary(pair.next, side: .start, from: time)
      setPlaceBoundary(pair.previous, side: .end, from: place)
      setPlaceBoundary(pair.next, side: .start, from: place)
    }

    unlinkNext(of: pair.previous, in: modelContext, suppress: false)
    unlinkPrevious(of: pair.next, in: modelContext, suppress: false)
    setLinked(previous: pair.previous, next: pair.next)
    let entries = try entriesByID(in: modelContext)
    var visitedEdges: Set<String> = []
    propagateLocation(
      from: pair.previous,
      side: .end,
      entries: entries,
      visitedEdges: &visitedEdges
    )
    propagateLocation(
      from: pair.next,
      side: .start,
      entries: entries,
      visitedEdges: &visitedEdges
    )
    if persist { try modelContext.save() }
  }

  static func unlink(
    _ entry: LogEntry,
    from neighbor: LogEntry,
    in modelContext: ModelContext,
    persist: Bool = true
  ) throws {
    let pair = chronologicalPair(entry, neighbor)
    if pair.previous.linkedNextEntryID == pair.next.id {
      pair.previous.linkedNextEntryID = nil
      pair.previous.suppressedNextEntryID = pair.next.id
    }
    if pair.next.linkedPreviousEntryID == pair.previous.id {
      pair.next.linkedPreviousEntryID = nil
      pair.next.suppressedPreviousEntryID = pair.previous.id
    }
    if persist { try modelContext.save() }
  }

  static func propagateTimeEdit(
    from entry: LogEntry,
    in modelContext: ModelContext
  ) throws {
    let entries = try entriesByID(in: modelContext)
    if let id = entry.linkedPreviousEntryID,
      let previous = entries[id],
      let value = boundary(of: entry, side: .start)
    {
      if entry.kind == .workout || previous.kind == .workout {
        if previous.endTime != value.time {
          clearLink(previous: previous, next: entry)
        }
      } else {
        setTimeBoundary(previous, side: .end, from: value)
      }
    }
    if let id = entry.linkedNextEntryID,
      let next = entries[id],
      let value = boundary(of: entry, side: .end)
    {
      if entry.kind == .workout || next.kind == .workout {
        if next.startTime != value.time {
          clearLink(previous: entry, next: next)
        }
      } else {
        setTimeBoundary(next, side: .start, from: value)
      }
    }
  }

  static func validateTimeEdit(
    entry: LogEntry,
    startTime: Date,
    endTime: Date,
    in modelContext: ModelContext
  ) throws {
    let entries = try entriesByID(in: modelContext)
    if let id = entry.linkedPreviousEntryID,
      entries[id]?.kind != .workout,
      let previousStart = entries[id]?.startTime,
      startTime <= previousStart
    {
      throw EntryLinkingError.invalidTimeRange
    }
    if let id = entry.linkedNextEntryID,
      entries[id]?.kind != .workout,
      let nextEnd = entries[id]?.endTime,
      endTime >= nextEnd
    {
      throw EntryLinkingError.invalidTimeRange
    }
  }

  static func propagateLocationEdit(
    from entry: LogEntry,
    role: EntryDetailLocationRole,
    in modelContext: ModelContext
  ) throws {
    let entries = try entriesByID(in: modelContext)
    var visitedEdges: Set<String> = []
    if role.affectsStartBoundary {
      if boundary(of: entry, side: .start) == nil {
        clearLink(at: .start, of: entry, entries: entries)
      } else {
        propagateLocation(
          from: entry,
          side: .start,
          entries: entries,
          visitedEdges: &visitedEdges
        )
      }
    }
    if role.affectsEndBoundary {
      if boundary(of: entry, side: .end) == nil {
        clearLink(at: .end, of: entry, entries: entries)
      } else {
        propagateLocation(
          from: entry,
          side: .end,
          entries: entries,
          visitedEdges: &visitedEdges
        )
      }
    }
  }

  static func boundary(
    of entry: LogEntry,
    side: EntryBoundarySide
  ) -> EntryBoundaryValue? {
    let time = side == .start ? entry.startTime : entry.endTime
    guard let time, let endpoint = locationEndpoint(of: entry, side: side),
      let location = endpoint.location
    else { return nil }
    return EntryBoundaryValue(
      time: time,
      timeZoneIdentifier: side == .start
        ? entry.startTimeZoneIdentifier
        : entry.endTimeZoneIdentifier,
      placeID: endpoint.place?.id,
      location: location,
      name: endpoint.place?.name
        ?? endpoint.rawName
        ?? location.preferredName
        ?? String(localized: "Location"),
      systemImage: endpoint.place?.systemImage
        ?? location.systemImage
        ?? .mappin
    )
  }

  static func summary(for entry: LogEntry) -> String {
    switch entry.kind {
    case .transit:
      let origin = boundary(of: entry, side: .start)?.name ?? "?"
      let destination = boundary(of: entry, side: .end)?.name ?? "?"
      return
        "\(entry.transitDetails?.type ?? String(localized: "Transit")) from \(origin) to \(destination)"
    case .placeVisit:
      return entry.placeVisitDetails?.description
        ?? "Stay at \(boundary(of: entry, side: .start)?.name ?? String(localized: "place"))"
    case .workout:
      return entry.workoutDetails?.activityName ?? String(localized: "Workout")
    case .wakeUp:
      return String(localized: "Sleep")
    }
  }

  private struct LocationEndpoint {
    let place: Place?
    let location: Location?
    let rawName: String?
  }

  private static func locationEndpoint(
    of entry: LogEntry,
    side: EntryBoundarySide
  ) -> LocationEndpoint? {
    switch entry.kind {
    case .transit:
      let details = entry.transitDetails
      return side == .start
        ? LocationEndpoint(
          place: details?.originPlace,
          location: details?.originLocation ?? details?.originPlace?.location,
          rawName: details?.originRawText
        )
        : LocationEndpoint(
          place: details?.destinationPlace,
          location: details?.destinationLocation ?? details?.destinationPlace?.location,
          rawName: details?.destinationRawText
        )
    case .placeVisit:
      let details = entry.placeVisitDetails
      return LocationEndpoint(
        place: details?.place,
        location: details?.location ?? details?.place?.location,
        rawName: details?.placeRawText
      )
    case .workout:
      let details = entry.workoutDetails
      if details?.movementKind == .moving {
        return side == .start
          ? LocationEndpoint(
            place: details?.originPlace,
            location: details?.originPlace?.location,
            rawName: nil
          )
          : LocationEndpoint(
            place: details?.destinationPlace,
            location: details?.destinationPlace?.location,
            rawName: nil
          )
      }
      return LocationEndpoint(
        place: details?.place,
        location: details?.place?.location,
        rawName: nil
      )
    case .wakeUp:
      return nil
    }
  }

  private static func setTimeBoundary(
    _ entry: LogEntry,
    side: EntryBoundarySide,
    from value: EntryBoundaryValue
  ) {
    guard entry.kind != .workout else { return }
    if side == .start {
      entry.startTime = value.time
      entry.startTimeZoneIdentifier = value.timeZoneIdentifier
    } else {
      entry.endTime = value.time
      entry.endTimeZoneIdentifier = value.timeZoneIdentifier
    }
    entry.weather = nil
    entry.endWeather = nil
    entry.timeConfidence = .manualOverride
    entry.transitDetails?.durationSource = .manualOverride
  }

  private static func setPlaceBoundary(
    _ entry: LogEntry,
    side: EntryBoundarySide,
    from value: EntryBoundaryValue
  ) {
    switch entry.kind {
    case .transit:
      if side == .start {
        entry.transitDetails?.originPlace = value.placeID.flatMap {
          id in entry.modelContext.flatMap { try? place(id, in: $0) }
        }
        entry.transitDetails?.originLocation = value.location
        entry.transitDetails?.originRawText = value.name
        entry.startTimeZoneIdentifier =
          value.location.timeZoneIdentifier
          ?? entry.startTimeZoneIdentifier
        entry.transitDetails?.fieldReviews.removeAll { $0.field == .origin }
      } else {
        entry.transitDetails?.destinationPlace = value.placeID.flatMap {
          id in entry.modelContext.flatMap { try? place(id, in: $0) }
        }
        entry.transitDetails?.destinationLocation = value.location
        entry.transitDetails?.destinationRawText = value.name
        entry.endTimeZoneIdentifier =
          value.location.timeZoneIdentifier
          ?? entry.endTimeZoneIdentifier
        entry.transitDetails?.fieldReviews.removeAll { $0.field == .destination }
      }
    case .placeVisit:
      entry.placeVisitDetails?.place = value.placeID.flatMap {
        id in entry.modelContext.flatMap { try? place(id, in: $0) }
      }
      entry.placeVisitDetails?.location = value.location
      entry.placeVisitDetails?.placeRawText = value.name
      entry.placeVisitDetails?.fieldReviews.removeAll { $0.field == .place }
    case .workout:
      let savedPlace = value.placeID.flatMap {
        id in entry.modelContext.flatMap { try? place(id, in: $0) }
      }
      if entry.workoutDetails?.movementKind == .moving {
        if side == .start {
          entry.workoutDetails?.originPlace = savedPlace
          entry.workoutDetails?.fieldReviews.removeAll { $0.field == .origin }
        } else {
          entry.workoutDetails?.destinationPlace = savedPlace
          entry.workoutDetails?.fieldReviews.removeAll { $0.field == .destination }
        }
      } else {
        entry.workoutDetails?.place = savedPlace
        entry.workoutDetails?.fieldReviews.removeAll { $0.field == .place }
      }
    case .wakeUp:
      break
    }
    entry.weather = nil
    entry.endWeather = nil
    updateNeedsReview(entry)
  }

  private static func locationsMatch(
    _ lhs: EntryBoundaryValue,
    _ rhs: EntryBoundaryValue
  ) -> Bool {
    if let lhsID = lhs.placeID, let rhsID = rhs.placeID {
      return lhsID == rhsID
    }
    return GuidedComposerLocationMatcher.sameLocation(
      lhs.location,
      rhs.location
    )
  }

  private static func propagateLocation(
    from entry: LogEntry,
    side: EntryBoundarySide,
    entries: [UUID: LogEntry],
    visitedEdges: inout Set<String>
  ) {
    let neighborID =
      side == .start
      ? entry.linkedPreviousEntryID
      : entry.linkedNextEntryID
    guard let neighborID,
      let neighbor = entries[neighborID],
      let value = boundary(of: entry, side: side)
    else { return }
    let edgeID = [entry.id.uuidString, neighborID.uuidString]
      .sorted().joined(separator: ":")
    guard visitedEdges.insert(edgeID).inserted else { return }

    let neighborSide: EntryBoundarySide = side == .start ? .end : .start
    if neighbor.kind == .workout && value.placeID == nil {
      if side == .start {
        clearLink(previous: neighbor, next: entry)
      } else {
        clearLink(previous: entry, next: neighbor)
      }
      return
    }
    setPlaceBoundary(neighbor, side: neighborSide, from: value)
    guard usesSingleLocation(neighbor) else { return }
    let oppositeSide: EntryBoundarySide = neighborSide == .start ? .end : .start
    propagateLocation(
      from: neighbor,
      side: oppositeSide,
      entries: entries,
      visitedEdges: &visitedEdges
    )
  }

  private static func usesSingleLocation(_ entry: LogEntry) -> Bool {
    entry.kind == .placeVisit
      || (entry.kind == .workout
        && entry.workoutDetails?.movementKind == .staticWorkout)
  }

  private static func chronologicalPair(
    _ lhs: LogEntry,
    _ rhs: LogEntry
  ) -> (previous: LogEntry, next: LogEntry) {
    let ordered = ordered([lhs, rhs])
    return (ordered[0], ordered[1])
  }

  private static func selectedValue(
    _ source: EntryLinkValueSource,
    currentIsPrevious: Bool,
    previous: EntryBoundaryValue,
    next: EntryBoundaryValue
  ) -> EntryBoundaryValue {
    return switch source {
    case .current: currentIsPrevious ? previous : next
    case .neighbor: currentIsPrevious ? next : previous
    }
  }

  private static func setLinked(previous: LogEntry, next: LogEntry) {
    previous.linkedNextEntryID = next.id
    next.linkedPreviousEntryID = previous.id
    if previous.suppressedNextEntryID == next.id {
      previous.suppressedNextEntryID = nil
    }
    if next.suppressedPreviousEntryID == previous.id {
      next.suppressedPreviousEntryID = nil
    }
  }

  private static func clearLink(previous: LogEntry, next: LogEntry) {
    if previous.linkedNextEntryID == next.id {
      previous.linkedNextEntryID = nil
    }
    if next.linkedPreviousEntryID == previous.id {
      next.linkedPreviousEntryID = nil
    }
  }

  private static func clearLink(
    at side: EntryBoundarySide,
    of entry: LogEntry,
    entries: [UUID: LogEntry]
  ) {
    switch side {
    case .start:
      if let id = entry.linkedPreviousEntryID, let previous = entries[id] {
        clearLink(previous: previous, next: entry)
      }
    case .end:
      if let id = entry.linkedNextEntryID, let next = entries[id] {
        clearLink(previous: entry, next: next)
      }
    }
  }

  private static func workoutBoundaryHasSavedPlace(
    _ entry: LogEntry,
    _ boundary: EntryBoundaryValue
  ) -> Bool {
    entry.kind != .workout || boundary.placeID != nil
  }

  private static func repairInvalidLinks(in entries: [LogEntry]) -> Bool {
    let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    var changed = false
    for previous in entries {
      guard let nextID = previous.linkedNextEntryID,
        let next = byID[nextID],
        !boundariesMatch(previous: previous, next: next)
      else { continue }
      clearLink(previous: previous, next: next)
      changed = true
    }
    return changed
  }

  private static func repairDanglingLinks(in entries: [LogEntry]) -> Bool {
    let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    var changed = false
    for entry in entries {
      if let id = entry.linkedPreviousEntryID,
        byID[id]?.linkedNextEntryID != entry.id
      {
        entry.linkedPreviousEntryID = nil
        changed = true
      }
      if let id = entry.linkedNextEntryID,
        byID[id]?.linkedPreviousEntryID != entry.id
      {
        entry.linkedNextEntryID = nil
        changed = true
      }
    }
    return changed
  }

  private static func unlinkNext(
    of entry: LogEntry,
    in modelContext: ModelContext,
    suppress: Bool
  ) {
    guard let id = entry.linkedNextEntryID else { return }
    entry.linkedNextEntryID = nil
    if suppress { entry.suppressedNextEntryID = id }
    if let next = try? entriesByID(in: modelContext)[id] {
      next.linkedPreviousEntryID = nil
      if suppress { next.suppressedPreviousEntryID = entry.id }
    }
  }

  private static func unlinkPrevious(
    of entry: LogEntry,
    in modelContext: ModelContext,
    suppress: Bool
  ) {
    guard let id = entry.linkedPreviousEntryID else { return }
    entry.linkedPreviousEntryID = nil
    if suppress { entry.suppressedPreviousEntryID = id }
    if let previous = try? entriesByID(in: modelContext)[id] {
      previous.linkedNextEntryID = nil
      if suppress { previous.suppressedNextEntryID = entry.id }
    }
  }

  private static func entriesByID(
    in modelContext: ModelContext
  ) throws -> [UUID: LogEntry] {
    Dictionary(
      uniqueKeysWithValues: try modelContext.fetch(
        FetchDescriptor<LogEntry>()
      ).map { ($0.id, $0) }
    )
  }

  private static func place(_ id: UUID, in context: ModelContext) throws -> Place? {
    try context.fetch(FetchDescriptor<Place>()).first { $0.id == id }
  }

  private static func updateNeedsReview(_ entry: LogEntry) {
    let hasFieldReviews: Bool =
      switch entry.kind {
      case .transit:
        !(entry.transitDetails?.fieldReviews.isEmpty ?? true)
      case .placeVisit:
        !(entry.placeVisitDetails?.fieldReviews.isEmpty ?? true)
      case .workout:
        !(entry.workoutDetails?.fieldReviews.isEmpty ?? true)
      case .wakeUp:
        false
      }
    entry.needsReview = entry.entryKindReviewReason != nil || hasFieldReviews
  }
}

nonisolated extension EntryDetailLocationRole {
  fileprivate var affectsStartBoundary: Bool {
    self == .origin || self == .place
  }

  fileprivate var affectsEndBoundary: Bool {
    self == .destination || self == .place
  }
}
