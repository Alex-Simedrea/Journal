import SwiftUI

struct EntryDetailPlaceComposition: View {
  let entry: LogEntry
  let onPresent: (EntryDetailRoute) -> Void

  var body: some View {
    VStack(spacing: 10) {
      EntryDetailAdaptivePair {
        EntryDetailCompositionTimeCard(
          entry: entry,
          editable: true,
          needsReview: entry.placeVisitDetails?.review(for: .time) != nil,
          onEdit: { onPresent(.time) }
        )
        EntryDetailPeopleCard(
          people: entry.people,
          needsReview: entry.placeVisitDetails?.review(for: .people) != nil,
          onEdit: { onPresent(.people) }
        )
      }
      EntryDetailWeatherPair(entry: entry)
    }
  }
}

struct EntryDetailTransitComposition: View {
  let entry: LogEntry
  let onPresent: (EntryDetailRoute) -> Void

  var body: some View {
    VStack(spacing: 10) {
      EntryDetailAdaptivePair {
        EntryDetailCompositionTimeCard(
          entry: entry,
          editable: true,
          needsReview: entry.transitDetails?.review(for: .time) != nil,
          onEdit: { onPresent(.time) }
        )
        if let details = entry.transitDetails {
          EntryDetailTransitCard(
            details: details,
            needsReview: details.review(for: .transitType) != nil,
            onEdit: { onPresent(.transitMetadata) }
          )
        } else {
          EntryDetailMissingCard(text: "Transit details need review")
        }
      }
      EntryDetailAdaptivePair {
        EntryDetailWeatherColumn(entry: entry)
        EntryDetailPeopleCard(
          people: entry.people,
          needsReview: entry.transitDetails?.review(for: .people) != nil,
          onEdit: { onPresent(.people) }
        )
      }
    }
  }
}

struct EntryDetailWorkoutComposition: View {
  let entry: LogEntry
  let onPresent: (EntryDetailRoute) -> Void

  var body: some View {
    VStack(spacing: 10) {
      EntryDetailAdaptivePair {
        EntryDetailCompositionTimeCard(
          entry: entry,
          editable: false,
          needsReview: false,
          onEdit: { onPresent(.time) }
        )
        if let details = entry.workoutDetails {
          EntryDetailWorkoutCard(details: details)
        } else {
          EntryDetailMissingCard(text: "Workout details unavailable")
        }
      }
      EntryDetailAdaptivePair {
        EntryDetailWeatherColumn(entry: entry)
        EntryDetailPeopleCard(
          people: entry.people,
          needsReview: false,
          onEdit: { onPresent(.people) }
        )
      }
    }
  }
}

private struct EntryDetailCompositionTimeCard: View {
  let entry: LogEntry
  let editable: Bool
  let needsReview: Bool
  let onEdit: () -> Void

  var body: some View {
    EntryDetailTimeCard(
      startTime: entry.startTime,
      endTime: entry.endTime,
      startTimeZoneIdentifier: entry.startTimeZoneIdentifier,
      endTimeZoneIdentifier: entry.endTimeZoneIdentifier,
      editable: editable,
      needsReview: needsReview,
      onEdit: onEdit
    )
  }
}

private struct EntryDetailWeatherPair: View {
  let entry: LogEntry

  var body: some View {
    EntryDetailAdaptivePair {
      EntryDetailEndpointWeatherCard(entry: entry, endpoint: .start)
      EntryDetailEndpointWeatherCard(entry: entry, endpoint: .end)
    }
  }
}

private struct EntryDetailWeatherColumn: View {
  let entry: LogEntry

  var body: some View {
    VStack(spacing: 7) {
      EntryDetailEndpointWeatherCard(entry: entry, endpoint: .start)
      EntryDetailEndpointWeatherCard(entry: entry, endpoint: .end)
    }
    .frame(maxHeight: .infinity)
  }
}

private struct EntryDetailEndpointWeatherCard: View {
  enum Endpoint {
    case start
    case end
  }

  let entry: LogEntry
  let endpoint: Endpoint

  var body: some View {
    EntryDetailWeatherCard(
      weather: endpoint == .start ? entry.weather : entry.endWeather,
      location: location,
      placeSystemImage: placeSymbol,
      time: endpoint == .start ? entry.startTime : entry.endTime,
      timeZoneIdentifier: endpoint == .start
        ? entry.startTimeZoneIdentifier
        : entry.endTimeZoneIdentifier
    )
  }

  private var location: Location? {
    switch (entry.kind, endpoint) {
    case (.transit, .start):
      entry.transitDetails?.originLocation
        ?? entry.transitDetails?.originPlace?.location
    case (.transit, .end):
      entry.transitDetails?.destinationLocation
        ?? entry.transitDetails?.destinationPlace?.location
    case (.placeVisit, _):
      entry.placeVisitDetails?.location
        ?? entry.placeVisitDetails?.place?.location
    case (.workout, .start):
      entry.workoutDetails?.movementKind == .moving
        ? entry.workoutDetails?.originLocation
        : entry.workoutDetails?.sourceLocation
          ?? entry.workoutDetails?.place?.location
    case (.workout, .end):
      entry.workoutDetails?.movementKind == .moving
        ? entry.workoutDetails?.destinationLocation
        : entry.workoutDetails?.sourceLocation
          ?? entry.workoutDetails?.place?.location
    case (.wakeUp, _):
      nil
    }
  }

  private var placeSymbol: PlaceSystemImage? {
    let savedSymbol: PlaceSystemImage? =
      switch (entry.kind, endpoint) {
      case (.transit, .start):
        entry.transitDetails?.originPlace?.systemImage
      case (.transit, .end):
        entry.transitDetails?.destinationPlace?.systemImage
      case (.placeVisit, _):
        entry.placeVisitDetails?.place?.systemImage
      case (.workout, .start):
        entry.workoutDetails?.movementKind == .moving
          ? entry.workoutDetails?.originPlace?.systemImage
          : entry.workoutDetails?.place?.systemImage
      case (.workout, .end):
        entry.workoutDetails?.movementKind == .moving
          ? entry.workoutDetails?.destinationPlace?.systemImage
          : entry.workoutDetails?.place?.systemImage
      case (.wakeUp, _):
        nil
      }
    return savedSymbol ?? (location == nil ? nil : .mappin)
  }
}

private struct EntryDetailAdaptivePair<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      content()
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

private struct EntryDetailMissingCard: View {
  let text: LocalizedStringResource

  var body: some View {
    Text(text)
      .foregroundStyle(.secondary)
      .frame(
        maxWidth: .infinity,
        minHeight: 88,
        maxHeight: .infinity
      )
      .background(.background, in: .rect(cornerRadius: 22))
  }
}
