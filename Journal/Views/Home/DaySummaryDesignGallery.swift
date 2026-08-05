#if DEBUG
import MapKit
import SwiftUI

struct DaySummaryDesignGallery: View {
    private var rows: [DaySummaryRowModel] {
        if ProcessInfo.processInfo.arguments.contains("-gallery-sparse") {
            return Array(DaySummaryGalleryFixtures.rows.suffix(2))
        }
        return DaySummaryGalleryFixtures.rows
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(
                                DaySummaryDatePresentation.dayTitle(
                                    for: row.summary.day
                                )
                            )
                            .font(.title3.weight(.semibold))

                            DaySummaryCardContent(model: row)
                        }
                    }
                }
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .contentMargins(.bottom, 44, for: .scrollContent)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("July")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {} label: {
                        Label("Choose date", systemImage: "calendar")
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {} label: {
                        Label("Profile", systemImage: "person.fill")
                    }
                }
            }
        }
    }
}

private enum DaySummaryGalleryFixtures {
    static let rows: [DaySummaryRowModel] = [
        // Small day: weather and wake-up remain compact while movement
        // expands only enough to balance their column.
        row(
            day: 12,
            people: false,
            photos: 0,
            wakeUp: true,
            featuredPlace: false
        ),
        // People stay compact; movement moves across and fills the short day.
        row(
            day: 13,
            people: true,
            photos: 0,
            wakeUp: false,
            featuredPlace: false
        ),
        // Two photos share a single compact visual row.
        row(
            day: 14,
            people: false,
            photos: 2,
            wakeUp: false,
            featuredPlace: false
        ),
        // A content-heavy day retains the larger presentation.
        row(
            day: 15,
            people: true,
            photos: 4,
            wakeUp: true,
            featuredPlace: true,
            movementTypeCount: 3
        ),
        // When there are multiple stationary places, the retained place tile
        // balances against a compact photo row.
        row(
            day: 16,
            people: false,
            photos: 2,
            wakeUp: false,
            featuredPlace: true
        ),
    ]

    private static func row(
        day: Int,
        people: Bool,
        photos: Int,
        wakeUp: Bool,
        overview: Bool = true,
        movement: Bool = true,
        featuredPlace: Bool = true,
        movementTypeCount: Int = 2
    ) -> DaySummaryRowModel {
        let key = TimelineDayKey(year: 2026, month: 7, day: day)
        let place = TimelineLocationSnapshot(
            name: "Reyna Beach",
            latitude: 44.213,
            longitude: 28.645,
            systemImage: .beach
        )
        let home = TimelineLocationSnapshot(
            name: "Home",
            latitude: 44.195,
            longitude: 28.625,
            systemImage: .house
        )
        let overviewData = TimelineOverviewData(
            markers: [
                TimelineMapMarker(location: home),
                TimelineMapMarker(location: place),
            ],
            paths: [
                TimelineMapPath(
                    id: UUID(),
                    kind: .workout,
                    coordinates: [
                        home.coordinate,
                        CLLocationCoordinate2D(
                            latitude: 44.203,
                            longitude: 28.632
                        ),
                        place.coordinate,
                    ]
                )
            ]
        )
        let occurrenceID = TimelineOccurrenceID(
            entryID: UUID(),
            day: key,
            timeZoneIdentifier: "Europe/Bucharest",
            role: .intervalDay
        )
        let summary = DaySummary(
            day: key,
            occurrences: [],
            overviewData: overview ? overviewData : TimelineOverviewData(),
            showsOverviewMap: overview,
            people: people
                ? [
                    TimelinePersonSnapshot(
                        id: UUID(),
                        name: "Emma",
                        contactIdentifier: nil
                    ),
                    TimelinePersonSnapshot(
                        id: UUID(),
                        name: "Sam",
                        contactIdentifier: nil
                    ),
                    TimelinePersonSnapshot(
                        id: UUID(),
                        name: "Daria",
                        contactIdentifier: nil
                    ),
                ]
                : [],
            peopleNeedReview: false,
            photos: (0..<photos).map {
                PhotoReference(assetLocalIdentifier: "gallery-photo-\($0)")
            },
            movement: movement
                ? DayMovementSummary(
                    icons: Array(
                        [
                            DayMovementIconKind.transit("Bolt"),
                            .transit("Train"),
                            .workout("figure.walk"),
                        ].prefix(movementTypeCount)
                    ).map { kind in
                        DayMovementIcon(
                            id: TimelineOccurrenceID(
                                entryID: UUID(),
                                day: key,
                                timeZoneIdentifier: "Europe/Bucharest",
                                role: .intervalDay
                            ),
                            kind: kind
                        )
                    },
                    distanceMeters: 14_000,
                    durationSeconds: 4_320,
                    needsReview: false
                )
                : nil,
            wakeUp: wakeUp
                ? DayWakeSummary(
                    wakeTime: Date(timeIntervalSince1970: 1_785_298_320),
                    durationSeconds: 29_520,
                    timeZoneIdentifier: "Europe/Bucharest"
                )
                : nil,
            featuredPlace: featuredPlace
                ? DayFeaturedPlace(
                    occurrenceID: occurrenceID,
                    location: place,
                    durationSeconds: 7_200,
                    timeZoneIdentifier: "Europe/Bucharest",
                    needsReview: false
                )
                : nil,
            weatherRequest: DayWeatherRequest(
                day: key,
                startDate: .now,
                endDate: .now.addingTimeInterval(86_400),
                latitude: place.latitude,
                longitude: place.longitude,
                timeZoneIdentifier: "Europe/Bucharest"
            ),
            needsReview: false,
            showsNeedsReviewPlaceholder: false
        )
        return DaySummaryRowModel(
            summary: summary,
            weatherState: .loaded(
                DayWeatherSummary(
                    condition: "clear",
                    symbolName: "sun.max.fill",
                    highTemperatureCelsius: 31,
                    maximumHumidity: 0.70,
                    date: .now
                )
            )
        )
    }
}
#endif
