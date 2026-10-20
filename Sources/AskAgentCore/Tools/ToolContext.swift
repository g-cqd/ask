internal import AemiJSON
internal import AskAI

/// Where a tool runs.
public struct ToolContext: Sendable, Equatable {
    public static func == (left: ToolContext, right: ToolContext) -> Bool {
        left.workingDirectory == right.workingDirectory && left.outputDirectory == right.outputDirectory
            && left.sandbox == right.sandbox && (left.approve == nil) == (right.approve == nil)
    }

    /// Relative paths resolve against this directory.
    public let workingDirectory: String
    /// Where commands' whole output is written, so a result cut to fit the context can name the rest; nil
    /// writes none.
    public let outputDirectory: String?
    /// What the tools may touch: checked by the file tools before they read or write, and applied to every command
    /// `bash` runs (ADR-0035).
    public let sandbox: SandboxPolicy
    /// Who is asked when a call's `sandbox` argument asks for more than `sandbox` allows; nil refuses (roadmap 0019).
    public let approve: SandboxApprover?

    /// A context rooted at `workingDirectory`.
    /// - Parameters:
    ///   - workingDirectory: where relative paths resolve and commands run.
    ///   - outputDirectory: where commands' whole output goes, or nil.
    ///   - sandbox: what the tools may touch; nothing is restricted by default, so a caller that wants protection says so.
    ///   - approve: who grants a call more than `sandbox` allows; nil, the default, refuses.
    public init(
        workingDirectory: String, outputDirectory: String? = nil, sandbox: SandboxPolicy = .unrestricted,
        approve: SandboxApprover? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.outputDirectory = outputDirectory
        self.sandbox = sandbox
        self.approve = approve
    }

    /// This context with `policy` for one call.
    func with(_ policy: SandboxPolicy) -> ToolContext {
        ToolContext(
            workingDirectory: workingDirectory, outputDirectory: outputDirectory, sandbox: policy, approve: approve)
    }
}
