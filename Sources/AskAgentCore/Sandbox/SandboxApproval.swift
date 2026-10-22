public import AskAI

/// A tool call whose `sandbox` argument asks for more than the run allows, put to the user (roadmap 0019).
public struct SandboxApproval: Sendable, Equatable {
    /// The tool the call is for.
    public let tool: String
    /// The call's whole input, so the question can show the command or path.
    public let input: JSONObject
    /// What the call asked for beyond the run, in words: `network any (this run allows localhost)`.
    public let asked: [String]
    /// The request a session grant remembers; nil for an operation (such as reset) that must always ask.
    public let request: SandboxRequest?

    /// A question about `request`, or an operation with no reusable grant.
    public init(tool: String, input: JSONObject, asked: [String], request: SandboxRequest?) {
        self.tool = tool
        self.input = input
        self.asked = asked
        self.request = request
    }
}

/// Answers a ``SandboxApproval``: true runs the call under what it asked for. Only the user may answer true; a
/// run without one (`ask -p`) has no approver, and a widening is refused.
public typealias SandboxApprover = @Sendable (SandboxApproval) async -> Bool
