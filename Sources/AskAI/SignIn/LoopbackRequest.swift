internal import Foundation

/// The request a browser makes to the callback listener, read strictly.
///
/// Only a plain origin-form `GET` is understood: HTTP/1.0 or 1.1, a path that starts with `/`, headers of `Name: value`.
/// Everything else is refused rather than guessed at, because the listener is reachable by any page the user has open.
struct LoopbackRequest: Equatable, Sendable {
    /// The most bytes of request head accepted: a callback is a few hundred.
    static let limit = 8 * 1024

    let method: String
    /// The path as sent, not decoded, so it is compared exactly.
    let path: String
    let query: [QueryString.Item]
    let host: String?

    /// The request in `bytes`, up to and including the blank line that ends the head.
    /// - Returns: nil when it is longer than ``limit``, not UTF-8, or not a plain origin-form request.
    init?(parsing bytes: [UInt8]) {
        guard bytes.count <= Self.limit, let text = String(validating: bytes, as: UTF8.self) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].allSatisfy({ $0.isASCII && $0.isUppercase }), !parts[0].isEmpty,
            parts[1].hasPrefix("/"), parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0"
        else { return nil }
        var hosts: [String] = []
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { return nil }
            if line[..<colon].lowercased() == "host" {
                hosts.append(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            }
        }
        guard hosts.count <= 1 else { return nil }
        let target = parts[1]
        let split = target.firstIndex(of: "?")
        method = String(parts[0])
        path = String(split.map { target[..<$0] } ?? target)
        guard let items = QueryString.items(in: split.map { String(target[target.index(after: $0)...]) } ?? "") else {
            return nil
        }
        query = items
        host = hosts.first
    }

    /// The value of `name`, when it is given exactly once.
    func value(of name: String) -> String? { QueryString.value(of: name, in: query) }

    /// Whether `host` names this machine on `port`: anything else is a page on the internet reaching a local server
    /// through the user's browser (DNS rebinding).
    static func allows(host: String?, port: UInt16) -> Bool {
        guard let host else { return false }
        return ["localhost:\(port)", "127.0.0.1:\(port)", "[::1]:\(port)"].contains(host.lowercased())
    }
}
