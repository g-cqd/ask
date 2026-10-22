/// The user's requested thinking policy. `default` leaves the provider's existing behaviour alone; it does not mean off.
/// Named levels are requests, not portable guarantees of a token count. Ultra is deliberately absent: the observed Codex
/// catalog advertises it, but that inference endpoint rejects the wire value (diary 2026-10-22-07).
public enum ThinkingLevel: String, Codable, Sendable, CaseIterable, CustomStringConvertible {
    case providerDefault = "default"
    case off, minimal, low, medium, high, xhigh, max

    /// Every accepted spelling, for configuration and command-line diagnostics.
    public static var choices: String { allCases.map(\.rawValue).joined(separator: ", ") }

    public var description: String { rawValue }

    var isEffort: Bool { self != .providerDefault && self != .off }
}
