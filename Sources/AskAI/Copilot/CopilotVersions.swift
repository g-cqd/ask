internal import AemiJSON
public import Foundation

/// The VS Code and Copilot Chat versions the Copilot connection names, read from the newest official build (``VSCodeBuild``) at most once
/// an hour, kept in a file beside the credentials; a
/// failed check keeps the last versions read, or ``CopilotClientVersion/known``, and is tried again after five minutes.
public struct CopilotVersions: Sendable {
    let cache: URL
    let transport: any HTTPTransport

    /// How long a check holds.
    static let freshFor: Double = 3_600
    /// How long after a failed check the next is tried.
    static let retryAfter: Double = 300

    public init(cache: URL, transport: any HTTPTransport) {
        self.cache = cache
        self.transport = transport
    }

    /// The versions beside `file`'s credentials.
    public init(beside file: CredentialFile, transport: any HTTPTransport) {
        self.init(
            cache: file.url.deletingLastPathComponent().appending(path: "copilot-vscode-version.json"),
            transport: transport
        )
    }

    /// The versions to send at `now`: the kept ones while they hold, else newly read ones.
    public func current(now: Double) async -> CopilotClientVersion {
        let kept = load()
        if let kept, now >= kept.at, now - kept.at < Self.freshFor { return kept.version }
        if let read = try? await VSCodeBuild(transport: transport).latest() {
            store(Stored(version: read, at: now))
            return read
        }
        let fallback = kept?.version ?? .known
        store(Stored(version: fallback, at: now - Self.freshFor + Self.retryAfter))
        return fallback
    }

    private func load() -> Stored? {
        guard let bytes = try? Data(contentsOf: cache), bytes.count <= 4_096,
            let stored = try? AemiJSON.JSONDecoder().decode(Stored.self, from: Array(bytes)),
            stored.version.isPlain, stored.at.isFinite
        else { return nil }
        return stored
    }

    private func store(_ stored: Stored) {
        guard let bytes = try? AemiJSON.JSONEncoder().encodeToBytes(stored) else { return }
        try? FileManager.default.createDirectory(
            at: cache.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? AtomicFile.replace(cache, with: bytes)
    }

    private struct Stored: Codable {
        let version: CopilotClientVersion
        let at: Double
    }
}
