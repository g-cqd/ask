/// What a key or token the server returns must look like before ask stores it or sends it anywhere.
enum SignInSecret {
    /// The longest secret accepted: far above any real key, far below a hostile body.
    static let longest = 16384

    /// Whether `value` is non-empty, bounded, and free of whitespace and control characters, which would break a
    /// header line or smuggle a second one.
    static func isValid(_ value: String?) -> Bool {
        guard let value, !value.isEmpty, value.utf8.count <= longest else { return false }
        return value.unicodeScalars.allSatisfy { !$0.properties.isWhitespace && $0.value > 0x1f && $0.value != 0x7f }
    }
}
