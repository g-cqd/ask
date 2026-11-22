internal import Foundation

/// When an Antigravity quota lifts, as its refusal says it (t117): a 429 whose message ends `Resets in 90h38m` is a usage limit that
/// waiting minutes will not change, unlike a per-minute rate limit, which says no such thing. Recorded wording, 2026-11-12: "Individual
/// quota reached. Please upgrade your subscription to increase your limits. Resets in 90h38m".
enum AgyQuotaReset {
    /// The seconds the message's `Resets in …` names, and the message without that phrase (ask says when it lifts in its own words);
    /// nil when the message has no such phrase or its duration does not read.
    static func reading(_ message: String) -> (seconds: Int, message: String)? {
        guard let phrase = message.range(of: "Resets in ", options: [.caseInsensitive, .backwards]) else { return nil }
        let duration = message[phrase.upperBound...].prefix { !$0.isWhitespace && $0 != "," }
        guard let seconds = seconds(in: duration.hasSuffix(".") ? duration.dropLast() : duration) else { return nil }
        var before = message[..<phrase.lowerBound].trimmingCharacters(in: .whitespaces)
        while before.last == "." || before.last == "," { before.removeLast() }
        return (seconds, before)
    }

    /// `90h38m`, `2d3h`, `38m12s` or `45s`: numbers with a unit each, in that order, at most 9 digits each.
    private static func seconds(in text: Substring) -> Int? {
        let units: [(Character, Int)] = [("d", 86_400), ("h", 3_600), ("m", 60), ("s", 1)]
        var total = 0
        var digits = ""
        var next = 0
        for character in text {
            if character.isASCII, character.isNumber, digits.count < 9 {
                digits.append(character)
                continue
            }
            guard let place = units[next...].firstIndex(where: { $0.0 == character }), let count = Int(digits) else {
                return nil
            }
            total += count * units[place].1
            (digits, next) = ("", place + 1)
        }
        return digits.isEmpty && next > 0 ? total : nil
    }
}
