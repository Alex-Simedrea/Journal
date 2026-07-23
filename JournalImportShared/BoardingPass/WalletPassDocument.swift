import CryptoKit
import Foundation
import PassKit
import ZIPFoundation

struct WalletPassDocument: Decodable {
    var organizationName: String?
    var description: String?
    var passTypeIdentifier: String?
    var serialNumber: String?
    var expirationDate: String?
    var relevantDate: String?
    var relevantDates: [WalletRelevantDate]?
    var boardingPass: WalletBoardingPass?
}

struct WalletRelevantDate: Decodable {
    var startDate: String?
    var endDate: String?
}

struct WalletBoardingPass: Decodable {
    var headerFields: [WalletPassField] = []
    var primaryFields: [WalletPassField] = []
    var secondaryFields: [WalletPassField] = []
    var auxiliaryFields: [WalletPassField] = []
    var transitType: String?

    private enum CodingKeys: String, CodingKey {
        case headerFields
        case primaryFields
        case secondaryFields
        case auxiliaryFields
        case transitType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        headerFields = try container.decodeIfPresent(
            [WalletPassField].self,
            forKey: .headerFields
        ) ?? []
        primaryFields = try container.decodeIfPresent(
            [WalletPassField].self,
            forKey: .primaryFields
        ) ?? []
        secondaryFields = try container.decodeIfPresent(
            [WalletPassField].self,
            forKey: .secondaryFields
        ) ?? []
        auxiliaryFields = try container.decodeIfPresent(
            [WalletPassField].self,
            forKey: .auxiliaryFields
        ) ?? []
        transitType = try container.decodeIfPresent(
            String.self,
            forKey: .transitType
        )
    }
}

struct WalletPassField: Decodable {
    var key: String
    var label: String?
    var value: WalletPassValue
}

enum WalletPassValue: Decodable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else {
            self = .other
        }
    }

    var displayString: String? {
        switch self {
        case .string(let value): value
        case .number(let value): value.formatted()
        case .boolean(let value): value ? "Yes" : "No"
        case .other: nil
        }
    }
}
