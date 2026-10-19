internal import AemiJSON
internal import AskAI

/// Where a tool runs.
public struct ToolContext: Sendable, Equatable {
    /// Relative paths resolve against this directory.
    public let workingDirectory: String
    /// Where commands' whole output is written, so a result cut to fit the context can name the rest; nil
    /// writes none.
    public let outputDirectory: String?

    /// A context rooted at `workingDirectory`.
    /// - Parameters:
    ///   - workingDirectory: where relative paths resolve and commands run.
    ///   - outputDirectory: where commands' whole output goes, or nil.
    public init(workingDirectory: String, outputDirectory: String? = nil) {
        self.workingDirectory = workingDirectory
        self.outputDirectory = outputDirectory
    }
}
