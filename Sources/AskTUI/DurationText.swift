internal import Foundation

/// A whole number of seconds as the screen writes it (`ui.localizedDurations`): the locale's abbreviated units (`2 min`), or a compact
/// clock (`2:00`).
enum DurationText {
    /// The locale's abbreviated units, leaving out the zero ones: `1 hr, 30 min`.
    static func localized(_ seconds: Int64, locale: Locale = .current) -> String {
        Duration.seconds(seconds)
            .formatted(
                Duration.UnitsFormatStyle(
                    allowedUnits: [.hours, .minutes, .seconds], width: .abbreviated, zeroValueUnits: .hide
                )
                .locale(locale))
    }

    /// A clock: `1:05:00`, `2:00`, and below a minute bare seconds, or `0:30` when `minutes` asks for the minutes always.
    static func clock(_ seconds: Int64, minutes: Bool = false) -> String {
        func padded(_ value: Int64) -> String { value < 10 ? "0\(value)" : String(value) }
        if seconds >= 3600 { return "\(seconds / 3600):\(padded(seconds / 60 % 60)):\(padded(seconds % 60))" }
        if seconds >= 60 || minutes { return "\(seconds / 60):\(padded(seconds % 60))" }
        return String(seconds)
    }
}
