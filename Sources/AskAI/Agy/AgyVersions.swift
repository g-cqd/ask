public import Foundation

/// The `agy` version Cloud Code requests name, read from the Antigravity CLI's own update service at most once an hour, kept in a file
/// beside the credentials. A failed or slow check keeps the last version read, or ``known``, and is tried again after
/// five minutes; no check holds a request for more than two seconds.
///
/// The server grows the model list with the version a request names, so a version frozen at build time loses models as `agy` moves on
/// (see ``AgyCloud``). The update service's root page says `Antigravity CLI auto updater is running! Stable Version: <version>.`, the
/// address `agy` itself checks; it is a status page, not a documented interface, so anything that does not match is ignored.
public struct AgyVersions: Sendable {
    let cache: URL
    let transport: any HTTPTransport
    let timeout: Double

    /// The newest `agy` when ask was built (the update service's stable version, 2026-11-12), used until a check succeeds.
    public static let known = "1.5.6"

    /// The update service `agy` checks.
    static let service = URL.constant("https://antigravity-cli-auto-updater-974169037036.us-central1.run.app")

    /// A version kept at `cache`, read through `transport`, holding a request for at most `timeout` seconds.
    public init(cache: URL, transport: any HTTPTransport, timeout: Double = 2) {
        self.cache = cache
        self.transport = transport
        self.timeout = timeout
    }

    /// The version beside `file`'s credentials.
    public static func beside(_ file: CredentialFile, transport: any HTTPTransport) -> AgyVersions {
        AgyVersions(
            cache: file.url.deletingLastPathComponent().appending(path: "agy-cli-version.json"),
            transport: transport
        )
    }

    /// The version to send at `now`: the kept one while it holds, else a newly read one.
    public func current(now: Double) async -> String {
        await KeptVersion(url: cache, isUsable: { $0.isPlainVersion })
            .current(now: now, fallback: Self.known) { await latest() }
    }

    /// The stable version the update service names, or nil when it is slow, refuses, or says something else.
    func latest() async -> String? {
        let (transport, timeout) = (transport, timeout)
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let request = HTTPRequest(
                    url: Self.service,
                    method: "GET",
                    headers: [("accept", "text/html")],
                    body: [],
                    allowsRedirects: false
                )
                guard let reply = try? await transport.collecting(request, limit: 4_096), reply.status == 200 else {
                    return nil
                }
                return Self.stableVersion(in: reply.body)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// The version in the page's `Stable Version: <version>` words, when it is plain.
    static func stableVersion(in page: [UInt8]) -> String? {
        let text = String(decoding: page, as: UTF8.self)
        guard let marker = text.range(of: "Stable Version: ") else { return nil }
        let word = text[marker.upperBound...].prefix { $0.isASCII && ($0.isNumber || $0 == ".") }
        let version = String(word.hasSuffix(".") ? word.dropLast() : word)
        return version.isPlainVersion ? version : nil
    }
}
