public import Foundation

/// When an entry was made or done, as the lists show it: `2026-11-01 14:05`, in `zone`.
public enum ListTime {
    public static func stamp(_ seconds: Int, in zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: Date(timeIntervalSince1970: Double(seconds))
        )
        let two = { (value: Int?) in
            let text = String(value ?? 0)
            return text.count < 2 ? "0" + text : text
        }
        return "\(parts.year ?? 0)-\(two(parts.month))-\(two(parts.day)) \(two(parts.hour)):\(two(parts.minute))"
    }

    public static var now: Int { Int(Date().timeIntervalSince1970) }
}
