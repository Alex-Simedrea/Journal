import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers

@testable import Journal

@Suite("Boarding pass import")
struct BoardingPassImportTests {
    @Test("Share loader accepts data-backed plain text")
    @MainActor
    func loadsDataBackedPlainText() async throws {
        let expected = #"""
        Air France 6634 on 17 May 2026

        Paris to Bucharest
        ↗ 12:03 GMT+2 CDG (3m Late)
        ↘ 15:49 GMT+3 OTP (1m Early)
        """#
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.utf8PlainText.identifier,
            visibility: .all
        ) { completion in
            completion(Data(expected.utf8), nil)
            return nil
        }

        let result = try await SharedPlainTextLoader.load(from: provider)

        #expect(result == expected)
    }

    @Test("Share loader detects UTF-16 plain text without a BOM")
    @MainActor
    func loadsUTF16PlainText() async throws {
        let expected = "Phoenix to Los Angeles\n↗ 11:59 MST PHX"
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.plainText.identifier,
            visibility: .all
        ) { completion in
            completion(expected.data(using: .utf16LittleEndian), nil)
            return nil
        }

        let result = try await SharedPlainTextLoader.load(from: provider)

        #expect(result == expected)
    }

    @Test("CFR-style train pass is extracted deterministically")
    func parsesTrainPass() throws {
        let json = Data(
            #"""
            {
              "formatVersion": 1,
              "organizationName": "CFR Călători",
              "description": "Bilete online CFR Călători",
              "passTypeIdentifier": "pass.ro.example.cfr",
              "serialNumber": "test-ticket",
              "relevantDates": [{
                "startDate": "2026-07-16T19:47:00+03:00",
                "endDate": "2026-07-16T22:05:00+03:00"
              }],
              "boardingPass": {
                "transitType": "PKTransitTypeTrain",
                "headerFields": [],
                "primaryFields": [
                  {"key":"departure","label":"București Nord","value":"19:47"},
                  {"key":"arrival","label":"Brașov","value":"22:05"}
                ],
                "secondaryFields": [],
                "auxiliaryFields": [
                  {"key":"trains","label":"Trenuri","value":"IC 536"}
                ]
              }
            }
            """#.utf8
        )

        let result = try BoardingPassImporter.parse(passJSONData: json)

        #expect(result.organizationName == "CFR Călători")
        #expect(result.transitTypeName == "Train")
        #expect(result.originName == "București Nord")
        #expect(result.destinationName == "Brașov")
        #expect(result.serviceIdentifier == "IC 536")
        #expect(result.startTime != nil)
        #expect(result.endTime != nil)
        #expect(result.warnings.isEmpty)
    }

    @Test("Generic passes remain reviewable instead of becoming flights")
    func genericPassDoesNotAssumeFlight() throws {
        let json = Data(
            #"""
            {
              "boardingPass": {
                "transitType": "PKTransitTypeGeneric",
                "primaryFields": [
                  {"key":"from","label":"From","value":"A"},
                  {"key":"to","label":"To","value":"B"}
                ]
              }
            }
            """#.utf8
        )

        let result = try BoardingPassImporter.parse(passJSONData: json)

        #expect(result.transitTypeName == nil)
        #expect(result.originName == "A")
        #expect(result.destinationName == "B")
        #expect(!result.warnings.isEmpty)
    }

    @Test("Delta pass uses journey fields rather than pass expiration")
    func parsesDeltaPass() throws {
        let json = Data(
            #"""
            {
              "organizationName":"Fly Delta",
              "description":"Delta Air Lines",
              "passTypeIdentifier":"pass.com.delta.ebp",
              "serialNumber":"sample",
              "relevantDate":"2026-05-09T07:05:00.000+03:00",
              "expirationDate":"2026-05-16T07:05:00Z",
              "boardingPass":{
                "headerFields":[{"key":"flightNumber2","value":"DL9685","label":"FLIGHT"}],
                "primaryFields":[
                  {"key":"depart","value":"OTP","label":"BUCHAREST"},
                  {"key":"destination","value":"AMS","label":"AMSTERDAM"}
                ],
                "backFields":[
                  {"key":"departsBack","value":"OTP: Bucharest, Romania, RO\n7:05AM, May 09, 2026","label":"DEPARTS"},
                  {"key":"arrivesBack","value":"AMS: Amsterdam, Netherlands, NL\n8:55AM, May 09, 2026","label":"ARRIVES"}
                ],
                "transitType":"PKTransitTypeAir"
              }
            }
            """#.utf8
        )

        let result = try BoardingPassImporter.parse(passJSONData: json)
        let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!

        #expect(result.originName == "Bucharest")
        #expect(result.originAirportCode == "OTP")
        #expect(result.destinationName == "Amsterdam")
        #expect(result.destinationAirportCode == "AMS")
        #expect(result.serviceIdentifier == "DL9685")
        #expect(
            result.startTime
                == ISO8601DateFormatter().date(from: "2026-05-09T04:05:00Z")
        )
        #expect(
            result.endLocalDateTime?.date(in: amsterdam)
                == ISO8601DateFormatter().date(from: "2026-05-09T06:55:00Z")
        )
        #expect(
            result.endTime
                != ISO8601DateFormatter().date(from: "2026-05-16T07:05:00Z")
        )
        #expect(result.warnings.isEmpty)
    }

    @Test("Flighty plain-text summary is imported with explicit time zones")
    func parsesFlightySummary() throws {
        let summary = #"""
        Air France 6634 on 17 May 2026

        Paris to Bucharest
        ↗ 12:03 GMT+2 CDG (3m Late)
        ↘ 15:49 GMT+3 OTP (1m Early)

        Flight length 2 hr, 46 min

        Arriving at Terminal MAIN • Gate F30 at 15:49 GMT+3

        Updates: https://live.flighty.app/bca8923a-1280-40da-a8c3-ab4863159055
        """#

        let result = try BoardingPassImporter.parse(flightSummary: summary)

        #expect(result.organizationName == "Air France")
        #expect(result.serviceIdentifier == "6634")
        #expect(result.transitTypeName == "Flight")
        #expect(result.originName == "Paris")
        #expect(result.originAirportCode == "CDG")
        #expect(result.destinationName == "Bucharest")
        #expect(result.destinationAirportCode == "OTP")
        #expect(
            result.startTime
                == ISO8601DateFormatter().date(from: "2026-05-17T10:03:00Z")
        )
        #expect(
            result.endTime
                == ISO8601DateFormatter().date(from: "2026-05-17T12:49:00Z")
        )
        #expect(result.warnings.isEmpty)
    }

    @Test("Flighty summaries support abbreviated local time zones")
    func parsesFlightySummaryWithTimeZoneAbbreviations() throws {
        let summary = #"""
        Air France 2389 on 16 May 2026

        Phoenix to Los Angeles
        ↗ 11:59 MST PHX (6m Early)
        ↘ 13:42 PDT LAX (8m Late)

        Flight length 1 hr, 43 min

        Arriving at Terminal 2 • Gate 21B at 13:42 PDT

        Updates: https://live.flighty.app/052fea77-cb6c-479a-bf6d-dfce607cca45
        """#

        let result = try BoardingPassImporter.parse(flightSummary: summary)

        #expect(result.organizationName == "Air France")
        #expect(result.serviceIdentifier == "2389")
        #expect(result.originName == "Phoenix")
        #expect(result.originAirportCode == "PHX")
        #expect(result.destinationName == "Los Angeles")
        #expect(result.destinationAirportCode == "LAX")
        #expect(
            result.startTime
                == ISO8601DateFormatter().date(from: "2026-05-16T18:59:00Z")
        )
        #expect(
            result.endTime
                == ISO8601DateFormatter().date(from: "2026-05-16T20:42:00Z")
        )
        #expect(result.warnings.isEmpty)
    }

    @Test("Flighty summaries tolerate share-sheet Unicode formatting")
    func parsesFlightySummaryWithInvisibleFormatting() throws {
        let summary = "Air France\u{202f}2389 on 16 May 2026\u{2028}"
            + "\u{2066}Phoenix to Los Angeles\u{2069}\u{2028}"
            + "↗\u{fe0f} 11:59 MST PHX (6m Early)\u{2028}"
            + "↘\u{fe0f} 13:42 PDT LAX (8m Late)"

        let result = try BoardingPassImporter.parse(flightSummary: summary)

        #expect(result.originAirportCode == "PHX")
        #expect(result.destinationAirportCode == "LAX")
    }

    @Test("Queued imports remain decodable after adding local flight times")
    func decodesEarlierPendingImport() throws {
        let json = Data(
            #"""
            {
              "id":"91F34298-F437-4226-A195-687A64A558CC",
              "importedAt":"2026-05-09T04:05:00Z",
              "sourceFingerprint":"existing-import",
              "organizationName":"Fly Delta",
              "warnings":[]
            }
            """#.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let result = try decoder.decode(PendingBoardingPassImport.self, from: json)

        #expect(result.organizationName == "Fly Delta")
        #expect(result.startLocalDateTime == nil)
        #expect(result.endLocalDateTime == nil)
        #expect(result.originAirportCode == nil)
        #expect(result.destinationAirportCode == nil)
    }

    @Test("Flight airport codes resolve to map locations before review")
    @MainActor
    func resolvesAirportLocations() async throws {
        let pendingImport = PendingBoardingPassImport(
            sourceFingerprint: "airport-resolution",
            transitTypeName: "Flight",
            originName: "Paris",
            originAirportCode: "CDG",
            destinationName: "Bucharest",
            destinationAirportCode: "OTP",
            startTime: ISO8601DateFormatter().date(
                from: "2026-05-17T10:03:00Z"
            ),
            endTime: ISO8601DateFormatter().date(
                from: "2026-05-17T12:49:00Z"
            )
        )
        let model = BoardingPassReviewModel(
            pendingImport: pendingImport,
            airportResolver: { code, _ in
                switch code {
                case "CDG":
                    Location(
                        latitude: 49.0097,
                        longitude: 2.5479,
                        displayName: "Paris Charles de Gaulle Airport",
                        timeZoneIdentifier: "Europe/Paris"
                    )
                case "OTP":
                    Location(
                        latitude: 44.5711,
                        longitude: 26.0850,
                        displayName: "Henri Coandă International Airport",
                        timeZoneIdentifier: "Europe/Bucharest"
                    )
                default:
                    nil
                }
            }
        )

        await model.prepare(places: [], transitTypes: [])
        let entry = model.makeDraftEntry(places: [])

        #expect(entry.transitDetails?.originLocation?.latitude == 49.0097)
        #expect(entry.transitDetails?.destinationLocation?.latitude == 44.5711)
        #expect(entry.startTimeZoneIdentifier == "Europe/Paris")
        #expect(entry.endTimeZoneIdentifier == "Europe/Bucharest")
        #expect(entry.transitDetails?.review(for: .origin) == nil)
        #expect(entry.transitDetails?.review(for: .destination) == nil)
        #expect(entry.transitDetails?.originRawText == "Paris (CDG)")
        #expect(entry.transitDetails?.destinationRawText == "Bucharest (OTP)")
    }

    @Test("Saving a flight creates reusable airport places")
    @MainActor
    func savesAirportPlaces() async throws {
        let pendingImport = PendingBoardingPassImport(
            sourceFingerprint: "airport-place-save",
            transitTypeName: "Flight",
            originName: "Paris",
            originAirportCode: "CDG",
            destinationName: "Bucharest",
            destinationAirportCode: "OTP",
            startTime: ISO8601DateFormatter().date(
                from: "2026-05-17T10:03:00Z"
            ),
            endTime: ISO8601DateFormatter().date(
                from: "2026-05-17T12:49:00Z"
            )
        )
        let model = BoardingPassReviewModel(
            pendingImport: pendingImport,
            airportResolver: { code, _ in
                switch code {
                case "CDG":
                    Location(
                        latitude: 49.0097,
                        longitude: 2.5479,
                        displayName: "Paris Charles de Gaulle Airport",
                        timeZoneIdentifier: "Europe/Paris",
                        cityName: "Roissy-en-France"
                    )
                case "OTP":
                    Location(
                        latitude: 44.5711,
                        longitude: 26.0850,
                        displayName: "Henri Coandă International Airport",
                        timeZoneIdentifier: "Europe/Bucharest",
                        cityName: "Otopeni"
                    )
                default:
                    nil
                }
            }
        )
        await model.prepare(places: [], transitTypes: [])
        let entry = model.makeDraftEntry(places: [])
        let context = try makeContext()

        try AirportPlaceStore.attachAirports(
            to: entry,
            originCode: pendingImport.originAirportCode,
            originCityName: model.originName,
            destinationCode: pendingImport.destinationAirportCode,
            destinationCityName: model.destinationName,
            in: context
        )
        context.insert(entry)
        try context.save()

        let places = try context.fetch(FetchDescriptor<Place>())
        let cdg = places.first { $0.aliases.contains("CDG") }
        let otp = places.first { $0.aliases.contains("OTP") }
        #expect(places.count == 2)
        #expect(cdg?.name == "Paris Charles de Gaulle Airport")
        #expect(cdg?.systemImage == .airport)
        #expect(cdg?.aliases.contains("Paris") == true)
        #expect(otp?.name == "Henri Coandă International Airport")
        #expect(otp?.systemImage == .airport)
        #expect(otp?.aliases.contains("Bucharest") == true)
        #expect(entry.transitDetails?.originPlace?.id == cdg?.id)
        #expect(entry.transitDetails?.destinationPlace?.id == otp?.id)
    }

    @Test("Flight imports prefer a saved IATA alias over a city place")
    @MainActor
    func reusesSavedAirportByCode() async throws {
        let city = Place(
            name: "Phoenix",
            location: Location(latitude: 33.4484, longitude: -112.0740)
        )
        let airport = Place(
            name: "Phoenix Sky Harbor International Airport",
            location: Location(latitude: 33.4342, longitude: -112.0116),
            systemImage: .airport
        )
        airport.aliases = ["PHX", "Phoenix"]
        let pendingImport = PendingBoardingPassImport(
            sourceFingerprint: "airport-place-reuse",
            transitTypeName: "Flight",
            originName: "Phoenix",
            originAirportCode: "PHX",
            startTime: .now,
            endTime: .now.addingTimeInterval(60 * 60)
        )
        let model = BoardingPassReviewModel(
            pendingImport: pendingImport,
            airportResolver: { _, _ in nil }
        )

        await model.prepare(places: [city, airport], transitTypes: [])

        #expect(model.originPlaceID == airport.id)
        #expect(model.originPlaceID != city.id)
    }

    @MainActor
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
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return ModelContext(container)
    }
}
