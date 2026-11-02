internal import AemiJSON
public import AskAI

/// Where a tool runs.
public struct ToolContext: Sendable, Equatable {
    public static func == (left: ToolContext, right: ToolContext) -> Bool {
        left.workingDirectory == right.workingDirectory && left.outputDirectory == right.outputDirectory
            && left.sandbox == right.sandbox && left.runSandbox == right.runSandbox
            && (left.approve == nil) == (right.approve == nil)
            && left.narrowing === right.narrowing && left.commandEnvironment == right.commandEnvironment
            && (left.destructiveApprover == nil) == (right.destructiveApprover == nil)
            && left.imageLimits == right.imageLimits && (left.callGate == nil) == (right.callGate == nil)
            && (left.progress == nil) == (right.progress == nil) && left.callID == right.callID
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
    /// What of ask's own environment a command may inherit (ADR-0106). Everything by default, so a caller that wants protection says so.
    public let commandEnvironment: CommandEnvironment
    /// Who is asked before a server's tool marked destructive runs; nil, the default, runs it unasked, as `ask -p` does (ADR-0111).
    public private(set) var destructiveApprover: DestructiveApprover?
    /// What is asked before a call that changes things runs (roadmap 0134); nil runs every call the sandbox allows, as `ask -p` does.
    public private(set) var callGate: ToolCallGate?
    /// What the model's provider accepts of images in one request, when it says; `read` fits pictures to it.
    public let imageLimits: ImageLimits?
    /// Who answers the model's questions (roadmap 0117); nil where no one can, and then the `question` tool is not offered.
    public let askPerson: PersonQuestion.Asker?
    /// Who is told how far a running call has got (roadmap 0067); nil where no one shows it, as in `ask -p`.
    public let progress: ToolProgressReporter?
    /// The call this context runs, set by the loop for each call; nil outside one.
    public private(set) var callID: String?

    /// A context rooted at `workingDirectory`.
    /// - Parameters:
    ///   - workingDirectory: where relative paths resolve and commands run.
    ///   - outputDirectory: where commands' whole output goes, or nil.
    ///   - sandbox: what the tools may touch; nothing is restricted by default, so a caller that wants protection says so.
    ///   - approve: who grants a call more than `sandbox` allows; nil, the default, refuses.
    ///   - narrowing: where the model's session-wide narrowing is kept; nil offers none.
    ///   - commandEnvironment: which of ask's variables a command is denied.
    ///   - destructiveApprover: who answers when a server marks its tool destructive; nil, the default, allows.
    ///   - imageLimits: what the model's provider accepts of images, or nil when it did not say.
    ///   - callGate: what is asked before a call that changes things; nil, the default, asks nothing.
    ///   - askPerson: who answers the model's questions; nil, the default, where no one can.
    ///   - progress: who is told how far a running call has got; nil, the default, where no one shows it.
    public init(
        workingDirectory: String,
        outputDirectory: String? = nil,
        sandbox: SandboxPolicy = .unrestricted,
        approve: SandboxApprover? = nil,
        narrowing: SessionNarrowing? = nil,
        commandEnvironment: CommandEnvironment = .inherit,
        destructiveApprover: DestructiveApprover? = nil,
        imageLimits: ImageLimits? = nil,
        callGate: ToolCallGate? = nil,
        askPerson: PersonQuestion.Asker? = nil,
        progress: ToolProgressReporter? = nil
    ) {
        self.progress = progress
        self.callGate = callGate
        self.askPerson = askPerson
        self.imageLimits = imageLimits
        self.workingDirectory = workingDirectory
        self.outputDirectory = outputDirectory
        self.sandbox = sandbox
        self.runSandbox = sandbox
        self.approve = approve
        self.narrowing = narrowing
        self.commandEnvironment = commandEnvironment
        self.destructiveApprover = destructiveApprover
    }

    /// This context without a server's own question before its tool: the person's `approvals.allow` names the tool.
    func withoutServerQuestion() -> ToolContext {
        var copy = self
        copy.destructiveApprover = nil
        return copy
    }

    /// This context for the call `id`, whose progress is reported under it.
    public func during(call id: String) -> ToolContext {
        var copy = self
        copy.callID = id
        return copy
    }

    /// This context with nothing asked before a call: for what the person configured to run, such as the check hook's command (0192).
    /// The sandbox still holds.
    public func withoutCallGate() -> ToolContext {
        var copy = self
        copy.callGate = nil
        return copy
    }

    /// This context with `first` answering its gate's approvals before the person; unchanged without a gate.
    func answering(first: @escaping @Sendable (ToolCallApproval) async -> ApprovalDecision) -> ToolContext {
        var copy = self
        copy.callGate?.first = first
        return copy
    }

    /// This context with `policy` for one call.
    func with(_ policy: SandboxPolicy) -> ToolContext {
        var copy = self
        copy.sandbox = policy
        return copy
    }
}
