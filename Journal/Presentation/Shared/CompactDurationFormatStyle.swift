import Foundation

struct CompactDurationFormatStyle: FormatStyle {
    func format(_ value: TimeInterval) -> String {
        let totalMinutes = max(0, Int((value / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        guard hours > 0 else {
            return "\(minutes)m"
        }

        guard minutes > 0 else {
            return "\(hours)h"
        }

        return "\(hours)h\(minutes)m"
    }
}

extension FormatStyle where Self == CompactDurationFormatStyle {
    static var compactDuration: CompactDurationFormatStyle {
        CompactDurationFormatStyle()
    }
}
