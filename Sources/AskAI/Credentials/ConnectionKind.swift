/// The built-in subscription behavior reused by a named connection. A connection is not another provider implementation.
public enum ConnectionKind: String, Codable, Sendable, CaseIterable {
    case anthropic
    case codex
}
