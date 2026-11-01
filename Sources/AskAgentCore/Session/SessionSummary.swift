internal import Foundation

/// What a session listing says about one session: how it began, and how many prompts it holds.
public struct SessionSummary: Sendable, Equatable {
    /// The user's first prompt, if any.
    public let firstPrompt: String?
    /// The user's prompts; ask's own continuation requests are not counted.
    public let prompts: Int

    /// Whether the session is encrypted and could not be read: no keys were given, or not its keys.
    public let isLocked: Bool

    /// The summary of `tree`'s active branch.
    public init(_ tree: SessionTree) {
        let prompts = tree.activeBranch()
            .compactMap { entry -> String? in
                guard case .user(let text) = entry.payload, text != AgentLoop.continuationPrompt,
                    text != AgentLoop.reconnectionPrompt
                else { return nil }
                return SkillInvocation.shown(text)
            }
        firstPrompt = prompts.first
        self.prompts = prompts.count
        isLocked = false
    }

    private init(locked: Void) {
        firstPrompt = nil
        prompts = 0
        isLocked = true
    }

    /// The summary of the session at `path`, read without opening it, so a session in use can still be listed; nil when the file cannot be
    /// read or is not a session. An encrypted session is read with `keyring`, and is ``isLocked`` without it.
    public init?(readingFrom path: String, keyring: SessionKeyring? = nil) {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let bytes = [UInt8](data)
        guard bytes.starts(with: FrameFormat.magic) else {
            guard let recovered = try? SessionLog.recover(bytes) else { return nil }
            self.init(recovered.tree)
            return
        }
        guard let header = try? FramedHeader.parse(bytes) else { return nil }
        var key: FileKey?
        if header.encrypted {
            guard let keyring, let opened = try? keyring.fileKey(envelope: header.envelope) else {
                self.init(locked: ())
                return
            }
            key = opened
        }
        guard let read = try? FramedReader.read(bytes, key: key?.key),
            let recovered = try? SessionLog.recover(read.records.flatMap { $0 + [0x0A] })
        else { return nil }
        self.init(recovered.tree)
    }
}
