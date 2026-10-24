/// What a token endpoint's answer must look like before it is stored: shared by every sign-in that renews a bearer token.
enum TokenSanity {
    /// A bearer token of sane size without whitespace.
    static func isToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf16.count <= 16_384 && !value.contains(where: \.isWhitespace)
    }

    /// A positive, finite lifetime in seconds that fits a date.
    static func isLifetime(_ seconds: Double) -> Bool { seconds > 0 && seconds.isFinite && seconds <= 8.64e12 }

    /// When to renew a token received at `now` that lives `lifetime` seconds: a tenth early, at most 300 s, so it is never used on
    /// its last second.
    static func renewal(from now: Double, lifetime: Double) -> Double { now + lifetime - Swift.min(300, lifetime / 10) }
}
