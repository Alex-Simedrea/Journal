import Foundation
import Testing

@testable import Journal

@Suite("Boarding pass import")
struct BoardingPassImportTests {
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
}
