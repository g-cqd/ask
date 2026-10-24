/// The claims of a token a server has just issued over TLS. Never verified, and never used to decide trust: only to show or route.
enum JWTPayload {
    /// The decoded middle part of a three-part token, or nil for any other shape or a part that is not base64url.
    static func bytes(of token: String) -> [UInt8]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        return Base64URL.decode(String(parts[1]))
    }
}
