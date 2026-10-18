internal import AemiJSON
internal import AskAI

/// Where a tool runs.
public struct ToolContext: Sendable, Equatable {
    /// Relative paths resolve against this directory.
    public let workingDirectory: String

    /// A context rooted at `workingDirectory`.
    public init(workingDirectory: String) { self.workingDirectory = workingDirectory }
}
