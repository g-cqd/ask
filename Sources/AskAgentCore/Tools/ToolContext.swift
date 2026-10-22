internal import AemiJSON
internal import AskAI

/// Where a tool runs.
public struct ToolContext: Sendable, Equatable {
    public static func == (left: ToolContext, right: ToolContext) -> Bool {
        left.workingDirectory == right.workingDirectory && left.outputDirectory == right.outputDirectory
            && left.sandbox == right.sandbox && left.runSandbox == right.runSandbox
            && (left.approve == nil) == (right.approve == nil)
            && left.narrowing === right.narrowing
    }

    /// Relative paths resolve against this directory.
    public let workingDirectory: String
    /// Where commands' whole output is written, so a result cut to fit the context can name the rest; nil
    /// writes none.
    public let outputDirectory: String?
    /// What the tools may touch: checked by the file tools before they read or write, and applied to every command
    /// `bash` runs (ADR-0035).
    public private(set) var sandbox: SandboxPolicy
    /// The run's policy before session and per-call narrowing; a session change never escapes this ceiling.
    public let runSandbox: SandboxPolicy
    /// Who is asked when a call's `sandbox` argument asks for more than `sandbox` allows; nil refuses (roadmap 0019).
    public let approve: SandboxApprover?
    /// The session-wide narrowing the model asked for, applied to every call; nil when the run offers none.
    public let narrowing: SessionNarrowing?

    /// A context rooted at `workingDirectory`.
    /// - Parameters:
    ///   - workingDirectory: where relative paths resolve and commands run.
    ///   - outputDirectory: where commands' whole output goes, or nil.
    ///   - sandbox: what the tools may touch; nothing is restricted by default, so a caller that wants protection says so.
    ///   - approve: who grants a call more than `sandbox` allows; nil, the default, refuses.
    ///   - narrowing: where the model's session-wide narrowing is kept; nil offers none.
    public init(
        workingDirectory: String, outputDirectory: String? = nil, sandbox: SandboxPolicy = .unrestricted,
        approve: SandboxApprover? = nil, narrowing: SessionNarrowing? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.outputDirectory = outputDirectory
        self.sandbox = sandbox
        self.runSandbox = sandbox
        self.approve = approve
        self.narrowing = narrowing
    }

    /// This context with `policy` for one call.
    func with(_ policy: SandboxPolicy) -> ToolContext {
        var copy = self
        copy.sandbox = policy
        return copy
    }
}
