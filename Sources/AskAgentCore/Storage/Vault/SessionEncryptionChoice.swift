/// The answer to the first-start question (ADR-0138's default), kept in the state directory rather than in `config.json`, which ask
/// would have to rewrite: whether sessions are encrypted, and whether the password is remembered. The settings win over it.
public struct SessionEncryptionChoice: Codable, Sendable, Equatable {
    public var encrypt: Bool
    public var remember: Bool

    public init(encrypt: Bool, remember: Bool) {
        self.encrypt = encrypt
        self.remember = remember
    }
}
