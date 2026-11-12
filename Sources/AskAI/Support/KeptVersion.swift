internal import AemiJSON
internal import Foundation

/// A version read from somewhere else, kept in a small JSON file with the time it was read, so that a check is skipped while it holds.
///
/// A check that fails keeps what was last read, or `fallback` when nothing was, and is tried again after `retryAfter`. A file that is
/// large, damaged, dated after now, or holds a value `isUsable` refuses is read as if it were not there, and is never sent.
struct KeptVersion<Value: Codable & Sendable>: Sendable {
    let url: URL
    let isUsable: @Sendable (Value) -> Bool

    /// How long a check holds.
    static var freshFor: Double { 3_600 }
    /// How long after a failed check the next is tried.
    static var retryAfter: Double { 300 }

    /// The value to use at `now`: the kept one while it holds, else one newly `read`, else the last kept, else `fallback`.
    func current(now: Double, fallback: Value, read: () async -> Value?) async -> Value {
        let kept = load()
        if let kept, now >= kept.at, now - kept.at < Self.freshFor { return kept.version }
        if let value = await read() {
            store(Stored(version: value, at: now))
            return value
        }
        let stale = kept?.version ?? fallback
        store(Stored(version: stale, at: now - Self.freshFor + Self.retryAfter))
        return stale
    }

    private func load() -> Stored? {
        guard let bytes = try? Data(contentsOf: url), bytes.count <= 4_096,
            let stored = try? AemiJSON.JSONDecoder().decode(Stored.self, from: Array(bytes)),
            isUsable(stored.version), stored.at.isFinite
        else { return nil }
        return stored
    }

    private func store(_ stored: Stored) {
        guard let bytes = try? AemiJSON.JSONEncoder().encodeToBytes(stored) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? AtomicFile.replace(url, with: bytes)
    }

    private struct Stored: Codable {
        let version: Value
        let at: Double
    }
}
