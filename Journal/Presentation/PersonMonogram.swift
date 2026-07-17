//
//  PersonMonogram.swift
//  Journal
//

import Foundation

enum PersonMonogram {
    static func initials(for name: String) -> String {
        let components = name
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard let first = components.first else { return "?" }
        if let last = components.last, components.count > 1 {
            return "\(first.prefix(1))\(last.prefix(1))".uppercased()
        }
        return String(first.prefix(2)).uppercased()
    }
}
