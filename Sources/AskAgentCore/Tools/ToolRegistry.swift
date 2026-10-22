internal import AemiJSON
public import AskAI

/// The tools available to a run, dispatched by name, with every output capped.
public struct ToolRegistry: Sendable {
    /// Two tools claimed one name.
    public struct DuplicateName: Error, Sendable, Equatable {
        public let name: String
    }

    private let tools: [String: any Tool]
    private let order: [String]
    private let cap: OutputCap

    /// A registry of `tools`, in the order given, capping outputs with `cap`.
    /// - Throws: ``DuplicateName`` when two tools share a name.
    public init(_ tools: [any Tool], cap: OutputCap = .standard) throws(DuplicateName) {
        var byName: [String: any Tool] = [:]
        for tool in tools {
            let name = tool.definition.name
            guard byName[name] == nil else { throw DuplicateName(name: name) }
            byName[name] = tool
        }
        self.tools = byName
        self.order = tools.map(\.definition.name)
        self.cap = cap
    }

    /// The tools' definitions, for the request.
    public var definitions: [ToolDefinition] { order.compactMap { tools[$0]?.definition } }

    /// Runs the tool called `name`.
    /// - Returns: its capped output, or an error output when no tool has that name.
    public func run(name: String, input: JSONObject, in context: ToolContext) async -> ToolOutput {
        guard let tool = tools[name] else {
            return .error("No tool is named \(name). Available: \(order.joined(separator: ", ")).")
        }
        // The session's narrowing applies to every call, and a call may narrow further, never widen (roadmap 0019).
        var context = context
        if let session = context.narrowing?.policy { context = context.with(context.sandbox.intersecting(session)) }
        do {
            if let request = try SandboxRequest.in(input) {
                switch request.applied(to: context.sandbox, workingDirectory: context.workingDirectory) {
                    case .narrowed(let policy): context = context.with(policy)
                    case .refused(let asked):
                        // Only the user widens: an approver asks them; without one the call is refused.
                        let question = SandboxApproval(tool: name, input: input, asked: asked, request: request)
                        if let approve = context.approve, await approve(question) {
                            context = context.with(
                                request.granted(over: context.sandbox, workingDirectory: context.workingDirectory))
                            break
                        }
                        return .error(
                            "This call asked for " + asked.joined(separator: " and ")
                                + ". Only the user can widen the sandbox: run it within what is allowed, or ask the user."
                        )
                    case .invalid(let reason): return .error("Invalid sandbox for \(name): \(reason).")
                }
            }
        } catch {
            return .error("Invalid sandbox for \(name): \(error).")
        }
        var output = await tool.run(input, in: context)
        output.content = cap.apply(output.content)
        return output
    }
}
