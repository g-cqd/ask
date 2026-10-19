internal import AemiJSON
internal import AskAI

/// Where a tool runs.
public struct ToolContext: Sendable, Equatable {
    /// Relative paths resolve against this directory.
    public let workingDirectory: String
    /// Where commands' whole output is written, so a result cut to fit the context can name the rest; nil
    /// writes none.
    public let outputDirectory: String?
    /// What the tools may touch: checked by the file tools before they read or write, and applied to every command
    /// `bash` runs (ADR-0035).
    public let sandbox: SandboxPolicy

    /// A context rooted at `workingDirectory`.
    /// - Parameters:
    ///   - workingDirectory: where relative paths resolve and commands run.
    ///   - outputDirectory: where commands' whole output goes, or nil.
    ///   - sandbox: what the tools may touch; nothing is restricted by default, so a caller that wants protection says so.
    public init(workingDirectory: String, outputDirectory: String? = nil, sandbox: SandboxPolicy = .unrestricted) {
        self.workingDirectory = workingDirectory
        self.outputDirectory = outputDirectory
        self.sandbox = sandbox
    }
}
