public import Foundation

/// The Antigravity application's OAuth client secret, read from the user's own installed `agy` and confirmed with Google.
///
/// Google stores such secrets as fixed-width strings in the binary's string table with nothing between them, so a greedy match
/// returns two run together, a value that is in no file. Candidates are therefore sliced to a width, and none is trusted for its
/// shape: only Google's own answer pairs one with the client (see ``verified(_:transport:)``).
public enum AgyClientSecret {
    /// The most probes one search may send, however many candidates a binary holds.
    public static let attemptLimit = 16

    private static let prefix = Array("GOCSPX-".utf8)
    private static let bodyWidths = 24 ... 40
    /// A real secret: the prefix and 28 characters.
    private static let exactLength = 35
    private static let longest = 7 + 40

    private static func isSecretByte(_ byte: UInt8) -> Bool {
        (0x30 ... 0x39).contains(byte) || (0x41 ... 0x5A).contains(byte) || (0x61 ... 0x7A).contains(byte)
            || byte == 0x2D
            || byte == 0x5F
    }

    /// Every well-formed candidate in `image`, exact length first.
    public static func candidates(in image: [UInt8]) -> [String] {
        var scan = Scan()
        scan.feed(image, final: true)
        return scan.result
    }

    /// Every well-formed candidate in the file, read in pieces so a 190 MB binary is never held whole.
    /// - Throws: ``AgySecretError/unreadable(path:)``.
    public static func candidates(inFileAt url: URL, chunkSize: Int = 4 << 20) throws(AgySecretError) -> [String] {
        var scan = Scan()
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            while let chunk = try handle.read(upToCount: Swift.max(chunkSize, 1)), !chunk.isEmpty {
                scan.feed(Array(chunk), final: false)
            }
        } catch { throw .unreadable(path: url.path) }
        scan.feed([], final: true)
        return scan.result
    }

    /// Candidates found so far, across the pieces of one image.
    private struct Scan {
        private var carry: [UInt8] = []
        private var exact: [String] = []
        private var other: [String] = []
        private var seen = Set<String>()

        var result: [String] { exact + other }

        /// Looks at every start with a full window after it, and keeps the rest for the next piece.
        mutating func feed(_ piece: [UInt8], final: Bool) {
            let buffer = carry + piece
            let limit = final ? buffer.count : Swift.max(0, buffer.count - (AgyClientSecret.longest - 1))
            var start = 0
            while start < limit {
                if buffer[start] == AgyClientSecret.prefix[0], matches(buffer, at: start) {
                    collect(buffer, from: start)
                }
                start += 1
            }
            carry = Array(buffer[limit...])
        }

        private func matches(_ buffer: [UInt8], at start: Int) -> Bool {
            let prefix = AgyClientSecret.prefix
            guard start + prefix.count <= buffer.count else { return false }
            return (0 ..< prefix.count).allSatisfy { buffer[start + $0] == prefix[$0] }
        }

        private mutating func collect(_ buffer: [UInt8], from start: Int) {
            let bodyStart = start + AgyClientSecret.prefix.count
            var run = 0
            while run < AgyClientSecret.bodyWidths.upperBound, bodyStart + run < buffer.count,
                AgyClientSecret.isSecretByte(buffer[bodyStart + run])
            {
                run += 1
            }
            for width in AgyClientSecret.bodyWidths where width <= run {
                let text = String(decoding: buffer[start ..< bodyStart + width], as: UTF8.self)
                guard seen.insert(text).inserted else { continue }
                if text.utf8.count == AgyClientSecret.exactLength { exact.append(text) } else { other.append(text) }
            }
        }
    }

    /// The first candidate Google accepts as the Antigravity client's secret: its token endpoint, given the client id, the candidate
    /// and a code that cannot be real, answers `invalid_grant` (HTTP 400) for the right pairing and `invalid_client` (HTTP 401) for
    /// a wrong one. The error code decides, not the status.
    /// - Returns: nil when none is accepted.
    /// - Throws: ``AgySecretError/inconclusive(status:)`` for any other answer, which says nothing about the pairing and must not
    ///   be taken for a rejection; or the transport's own error.
    public static func verified(_ candidates: [String], transport: any HTTPTransport) async throws -> String? {
        for candidate in candidates.prefix(attemptLimit) {
            let reply = try await transport.collecting(probe(candidate))
            let error = (try? OAuthErrorBody.code(in: reply.body)) ?? nil
            if reply.status == 400, error == "invalid_grant" { return candidate }
            if error != "invalid_client" { throw AgySecretError.inconclusive(status: reply.status) }
        }
        return nil
    }

    private static func probe(_ candidate: String) -> HTTPRequest {
        let fields = [
            ("client_id", AgyOAuth.clientID), ("client_secret", candidate), ("grant_type", "authorization_code"),
            ("code", "not-a-real-code"), ("redirect_uri", AgyOAuth.redirectURI)
        ]
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let body = fields.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
        return HTTPRequest(
            url: URL(string: AgyOAuth.tokenURL)!, method: "POST",
            headers: [("content-type", "application/x-www-form-urlencoded"), ("accept", "application/json")],
            body: Array(body.utf8))
    }
}
