/// How a session file is kept on disk (ADR-0138): plain JSONL, or a framed file, compressed, encrypted, or both.
public struct SessionFormat: Sendable, Equatable {
    public var compressed: Bool
    public var encrypted: Bool

    public init(compressed: Bool, encrypted: Bool) {
        self.compressed = compressed
        self.encrypted = encrypted
    }

    /// JSONL, as sessions were always written: readable with `cat` and `jq`.
    public static let plain = SessionFormat(compressed: false, encrypted: false)

    /// Whether the file is a framed one rather than JSONL.
    var isFramed: Bool { compressed || encrypted }
}
