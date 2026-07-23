import Foundation

enum BoardingPassImportDeepLink {
    static let scheme = "attractivestar-journal"
    static let host = "boarding-pass-import"
    static let url = URL(string: "\(scheme)://\(host)")!

    static func matches(_ url: URL) -> Bool {
        url.scheme == scheme && url.host == host
    }
}
