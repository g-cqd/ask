/// What a run does about encryption: the settings (`sessionEncryption`, `sessionPassword`, a workspace's overriding the user's either way)
/// first, then the first-start answer; with neither, the first-start question is asked.
public struct SessionEncryptionPolicy: Sendable, Equatable {
    public let mode: SessionEncryptionMode
    /// Whether the user key is kept in the keychain.
    public let remember: Bool
    /// No setting and no answer yet: ask, then record the answer.
    public let needsFirstStartQuestion: Bool

    public init(setting: SessionEncryptionMode?, password: SessionPasswordMode?, choice: SessionEncryptionChoice?) {
        mode = setting ?? (choice.map { $0.encrypt ? .on : .off } ?? .off)
        remember = password.map { $0 == .remember } ?? choice?.remember ?? true
        needsFirstStartQuestion = setting == nil && choice == nil
    }
}
