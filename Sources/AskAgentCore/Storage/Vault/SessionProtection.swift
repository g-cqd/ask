/// How a run keeps the sessions it makes (ADR-0138): their format, and the keys an encrypted one is sealed under.
public struct SessionProtection: Sendable {
    public let format: SessionFormat
    public let keyring: SessionKeyring?

    public init(format: SessionFormat, keyring: SessionKeyring?) {
        self.format = format
        self.keyring = keyring
    }

    /// JSONL, as sessions were always kept.
    public static let plain = SessionProtection(format: .plain, keyring: nil)
}
