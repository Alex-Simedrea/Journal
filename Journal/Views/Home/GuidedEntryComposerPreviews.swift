#if DEBUG
import SwiftUI

private struct GuidedComposerSuggestionPreviewCanvas: View {
    let model: GuidedEntryComposerModel
    let heading: String

    var body: some View {
        ZStack(alignment: .bottom) {
            GuidedComposerPreviewBackdrop(heading: heading)

            GuidedComposerSuggestionPanel(model: model)
                .padding(12)
        }
        .frame(width: 402, height: 700)
        .clipped()
    }
}

private struct GuidedComposerPreviewBackdrop: View {
    let heading: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.cyan.opacity(0.22),
                    Color.indigo.opacity(0.12),
                    Color.orange.opacity(0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.pink.opacity(0.28))
                .frame(width: 220, height: 220)
                .blur(radius: 22)
                .offset(x: 150, y: -230)

            Circle()
                .fill(.cyan.opacity(0.3))
                .frame(width: 180, height: 180)
                .blur(radius: 18)
                .offset(x: -150, y: 100)

            VStack(alignment: .leading, spacing: 24) {
                Text(heading)
                    .font(.largeTitle.bold())

                GuidedComposerPreviewTimelineRow(
                    time: "12:00",
                    title: "Reyna Beach",
                    color: .green,
                    systemImage: "beach.umbrella.fill"
                )
                GuidedComposerPreviewTimelineRow(
                    time: "13:00",
                    title: "Bolt · 20 min",
                    color: .blue,
                    systemImage: "car.fill"
                )
                GuidedComposerPreviewTimelineRow(
                    time: "13:20",
                    title: "Home",
                    color: .orange,
                    systemImage: "house.fill"
                )

                Spacer()
            }
            .padding(24)
        }
        .background(.background)
    }
}

private struct GuidedComposerPreviewTimelineRow: View {
    let time: String
    let title: String
    let color: Color
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Text(time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            Image(systemName: systemImage)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(color, in: Circle())

            Text(title)
                .font(.headline)
        }
    }
}

private enum GuidedComposerSuggestionPreviewData {
    static let compact = [
        suggestion(
            "stay",
            title: "Stay",
            subtitle: "Place visit",
            systemImage: "mappin.and.ellipse",
            semanticValue: .leading(.placeVisit(description: nil))
        ),
        suggestion(
            "bolt",
            title: "Bolt",
            subtitle: "Ride share",
            systemImage: "car.fill",
            semanticValue: .leading(.transit(canonicalName: "Bolt"))
        ),
        suggestion(
            "bicycle",
            title: "Bicycle",
            subtitle: "Transit",
            systemImage: "bicycle",
            semanticValue: .leading(
                .transit(canonicalName: "Bicycle")
            )
        ),
        suggestion(
            "description",
            title: "Use “Watch The Odyssey”",
            subtitle: "Place visit description",
            systemImage: "text.quote",
            semanticValue: .leading(
                .placeVisit(description: "Watch The Odyssey")
            )
        ),
    ]

    static let routes = [
        suggestion(
            "route-beach",
            title: "from Home at 11:38 to Reyna Beach at 12:00",
            subtitle: "Arrive before Reyna Beach",
            systemImage: "arrow.triangle.swap"
        ),
        suggestion(
            "route-home",
            title: "from Reyna Beach at 13:00 to Home at 13:20",
            subtitle: "Leave after Reyna Beach · MapKit 20 min",
            systemImage: "car.fill"
        ),
        suggestion(
            "route-address",
            title:
                "from Bulevardul Alexandru Lăpușneanu 116C to Home – Constanța",
            subtitle: "MapKit duration, anchored to timeline",
            systemImage: "map"
        ),
        suggestion(
            "route-gap",
            title: "from AFI Brașov at 17:40 to Gara Brașov at 18:05",
            subtitle: "Between Coffee and Train",
            systemImage: "clock.arrow.circlepath"
        ),
        suggestion(
            "route-workout",
            title: "from first Walk destination to Home",
            subtitle: "Leave after Walk",
            systemImage: "figure.walk"
        ),
        suggestion(
            "route-current",
            title: "from Current Location to Home",
            subtitle: "Leave from here now",
            systemImage: "location.fill"
        ),
        suggestion(
            "route-manual",
            title: "Search for another destination",
            subtitle: "Saved places and MapKit",
            systemImage: "magnifyingglass"
        ),
        suggestion(
            "route-museum",
            title: "from Home to Museum of National History",
            subtitle: "Arrive before Museum",
            systemImage: "building.columns.fill"
        ),
        suggestion(
            "route-airport",
            title: "from Henri Coandă Airport to Home – Constanța",
            subtitle: "Leave after Flight",
            systemImage: "airplane.arrival"
        ),
        suggestion(
            "route-steven",
            title: "from Steven’s place to Home",
            subtitle: "Another nearby Home is available",
            systemImage: "house.and.flag.fill"
        ),
    ]

    static let times = [
        suggestion(
            "time-mapkit",
            title: "12:00",
            subtitle: "MapKit · 22 min",
            systemImage: "map",
            semanticValue: previewTime
        ),
        suggestion(
            "time-1145",
            title: "11:45",
            subtitle: "15 minutes before arrival",
            systemImage: "clock",
            semanticValue: previewTime
        ),
        suggestion(
            "time-1130",
            title: "11:30",
            subtitle: "30 minutes before arrival",
            systemImage: "clock",
            semanticValue: previewTime
        ),
        suggestion(
            "time-1100",
            title: "11:00",
            subtitle: "60 minutes before arrival",
            systemImage: "clock",
            semanticValue: previewTime
        ),
    ]

    static let places = [
        placeSuggestion(
            "place-home",
            title: "Home – Constanța",
            subtitle: "Strada Mircea cel Bătrân 102, Constanța",
            systemImage: .house
        ),
        placeSuggestion(
            "place-beach",
            title: "Reyna Beach",
            subtitle: "Bulevardul Mamaia, Constanța",
            systemImage: .beach
        ),
        placeSuggestion(
            "place-mapkit",
            title: "Reyna Beach Bar",
            subtitle: "Mamaia-Sat, Năvodari",
            systemImage: .mappin
        ),
    ]

    private static let previewTime = ComposerTokenValue.time(
        ComposerTimeValue(
            date: .now,
            timeZoneIdentifier: TimeZone.current.identifier,
            source: .explicit
        ),
        .start
    )

    private static func placeSuggestion(
        _ id: String,
        title: String,
        subtitle: String?,
        systemImage: PlaceSystemImage
    ) -> ComposerSuggestion {
        let location = ComposerLocationCandidate(
            id: "preview-location-\(id)",
            displayName: title,
            location: Location(latitude: 44.2, longitude: 28.6),
            systemImage: systemImage,
            source: .savedPlace
        )
        return suggestion(
            id,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage.rawValue,
            semanticValue: .location(location, .visit)
        )
    }

    private static func suggestion(
        _ id: String,
        title: String,
        subtitle: String?,
        systemImage: String,
        semanticValue: ComposerTokenValue? = nil
    ) -> ComposerSuggestion {
        ComposerSuggestion(
            id: "preview-\(id)",
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            kind: semanticValue.map {
                .value(
                    tokens: [
                        ComposerToken(displayText: title, value: $0),
                    ],
                    nextSlot: .connector
                )
            } ?? .semanticSplit(bindings: [], nextSlot: .connector),
            score: 0
        )
    }
}

#Preview("Suggestions · Compact") {
    GuidedComposerSuggestionPreviewCanvas(
        model: .preview(
            suggestions: GuidedComposerSuggestionPreviewData.compact
        ),
        heading: "Entry type"
    )
}

#Preview("Suggestions · Long routes") {
    GuidedComposerSuggestionPreviewCanvas(
        model: .preview(
            suggestions: GuidedComposerSuggestionPreviewData.routes
        ),
        heading: "Route suggestions"
    )
    .environment(\.colorScheme, .dark)
}

#Preview("Suggestions · Time picker") {
    GuidedComposerSuggestionPreviewCanvas(
        model: .preview(
            suggestions: GuidedComposerSuggestionPreviewData.times,
            activeSlot: .time(.start)
        ),
        heading: "Departure time"
    )
}

#Preview("Suggestions · Loading and error") {
    GuidedComposerSuggestionPreviewCanvas(
        model: .preview(
            suggestions: GuidedComposerSuggestionPreviewData.places,
            activeSlot: .location(.destination),
            isSearchingPlaces: true,
            isCalculatingRoutes: true,
            locationStatusMessage: "Current location is unavailable."
        ),
        heading: "Destination"
    )
    .environment(\.dynamicTypeSize, .accessibility1)
}
#endif
