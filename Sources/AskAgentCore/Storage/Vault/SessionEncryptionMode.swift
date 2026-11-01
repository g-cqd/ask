/// `sessionEncryption` (roadmap 0182): whether new sessions are encrypted.
public enum SessionEncryptionMode: String, Sendable, CaseIterable {
    case off
    case on
    /// Asked when each new session begins.
    case ask

    static let choices = #""off", "on" or "ask""#
}
