internal import Foundation

/// What a session listing says about one session: how it began, and how many prompts it holds.
public struct SessionSummary: Sendable, Equatable {
    /// The user's first prompt, if any.
    public let firstPrompt: String?
    /// The user's prompts; ask's own continuation requests are not counted.
    public let prompts: Int

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
    }

    /// The summary of the session at `path`, read without opening it, so a session in use can still be listed;
    /// nil when the file cannot be read or is not a session.
    /// - Parameter path: the session file.
    public init?(readingFrom path: String) {
        guard let data = FileManager.default.contents(atPath: path),
            let recovered = try? SessionLog.recover([UInt8](data))
        else { return nil }
        self.init(recovered.tree)
    }
}
