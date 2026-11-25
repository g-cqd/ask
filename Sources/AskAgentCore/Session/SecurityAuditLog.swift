internal import AemiJSON
public import Foundation
internal import Synchronization

/// Bounded, secret-free, JSON-Lines security event log for enterprise SIEM export (R-OPS-1 / Sprint 3).
/// Lives under `$XDG_STATE_HOME/ask/security-audit.jsonl` (mode `0600`, auto-rotated at 1 MiB to `.1.jsonl`), inside the
/// state directory Seatbelt already denies write access to for sandboxed child commands.
/// Never records prompt bodies, command arguments, API keys, OAuth tokens, or file contents.
public final class SecurityAuditLog: Sendable {
    public struct Event: Codable, Equatable, Sendable {
        public let timestamp: String
        public let kind: String
        public let outcome: String
        public let attributes: [String: String]

        public init(timestamp: String, kind: String, outcome: String, attributes: [String: String] = [:]) {
            self.timestamp = timestamp
            self.kind = kind
            self.outcome = outcome
            self.attributes = attributes
        }
    }

    public static let maximumFileBytes = 1 << 20
    public static let maximumAttributeLength = 160

    public let fileURL: URL
    private let lock = Mutex(())

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Default audit log path under `stateRoot` (`~/.local/state/ask/security-audit.jsonl`).
    public static func defaultLog(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> SecurityAuditLog {
        let root = SessionDirectory.stateRoot(environment: environment, home: home)
        return SecurityAuditLog(
            fileURL: URL(fileURLWithPath: root, isDirectory: true).appending(path: "security-audit.jsonl")
        )
    }

    /// Appends one sanitized single-line JSONL event (`0600`), rotating when `maximumFileBytes` is reached.
    public func record(
        kind: String,
        outcome: String,
        attributes: [String: String] = [:],
        at timestamp: Date = Date()
    ) {
        let iso = ISO8601DateFormatter().string(from: timestamp)
        let bounded = attributes.mapValues { Self.sanitize($0) }
        let event = Event(
            timestamp: iso,
            kind: Self.sanitize(kind),
            outcome: Self.sanitize(outcome),
            attributes: bounded
        )
        guard var bytes = try? AemiJSON.JSONEncoder().encodeToBytes(event) else { return }
        bytes.append(0x0A)
        let line = Data(bytes)
        lock.withLock { _ in
            Self.append(line, to: fileURL)
        }
    }

    /// Reads all valid entries currently stored in `fileURL` (for SIEM export or inspection).
    public func readEvents() -> [Event] {
        lock.withLock { _ in
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            let decoder = AemiJSON.JSONDecoder()
            return data.split(separator: 0x0A)
                .compactMap { slice in
                    try? decoder.decode(Event.self, from: Array(slice))
                }
        }
    }

    private static func sanitize(_ value: String) -> String {
        let singleLine =
            value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return String(singleLine.prefix(maximumAttributeLength))
    }

    private static func append(_ line: Data, to url: URL) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue,
            size + line.count > maximumFileBytes
        {
            let rotated = url.deletingPathExtension().appendingPathExtension("1.jsonl")
            try? fm.removeItem(at: rotated)
            // try?: best-effort rotation of the security audit log; logging must never crash or block user approvals
            try? fm.moveItem(at: url, to: rotated)
        }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: line, attributes: [.posixPermissions: 0o600])
            return
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }
}
