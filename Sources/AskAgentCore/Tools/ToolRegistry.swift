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
    private let live: LiveTools?

    /// A registry of `tools`, in the order given, capping outputs with `cap`, and after them whatever `live` offers.
    /// - Throws: ``DuplicateName`` when two tools share a name.
    public init(_ tools: [any Tool], cap: OutputCap = .standard, live: LiveTools? = nil) throws(DuplicateName) {
        var byName: [String: any Tool] = [:]
        for tool in tools {
            let name = tool.definition.name
            guard byName[name] == nil else { throw DuplicateName(name: name) }
            byName[name] = tool
        }
        self.tools = byName
        self.order = tools.map(\.definition.name)
        self.cap = cap
        self.live = live
    }

    /// The tools' definitions, for the request.
    public var definitions: [ToolDefinition] {
        order.compactMap { tools[$0]?.definition } + offered().map(\.definition)
    }

    /// What the live tools offer now, without the names the built-in tools hold.
    private func offered() -> [any Tool] { live?.snapshot(excluding: Set(order)) ?? [] }

    /// Runs the tool called `name`.
    /// - Returns: its capped output, or an error output when no tool has that name.
    public func run(name: String, input: JSONObject, in context: ToolContext) async -> ToolOutput {
        // The session's narrowing applies to every call, and a call may narrow further, never widen (roadmap 0019).
        var context = context
        if let session = context.narrowing?.policy { context = context.with(context.sandbox.intersecting(session)) }
        var output: ToolOutput
        if let tool = tools[name] {
            switch await applyingRequest(of: name, input: input, to: context) {
                case .run(let narrowed): output = await tool.run(input, in: narrowed)
                case .refused(let refusal): return refusal
            }
        } else if let tool = offered().first(where: { $0.definition.name == name }) {
            // A foreign tool's arguments are its own: a `sandbox` among them is not a request to narrow ask's sandbox.
            output = await tool.run(input, in: context)
        } else {
            let names = order + offered().map(\.definition.name)
            return .error("No tool is named \(name). Available: \(names.joined(separator: ", ")).")
        }
        output.content = cap.apply(output.content)
        return output
    }

    /// Where a built-in call goes next: into a context, or back to the model refused.
    private enum Applied {
        case run(ToolContext)
        case refused(ToolOutput)
    }

    /// The context a built-in tool runs in once the call's own `sandbox` request, if it made one, is applied; or the refusal to return.
    private func applyingRequest(
        of name: String, input: JSONObject, to context: ToolContext
    ) async -> Applied {
        do {
            guard let request = try SandboxRequest.in(input) else { return .run(context) }
            switch request.applied(to: context.sandbox, workingDirectory: context.workingDirectory) {
                case .narrowed(let policy): return .run(context.with(policy))
                case .refused(let asked):
                    // Only the user widens: an approver asks them; without one the call is refused.
                    let question = SandboxApproval(tool: name, input: input, asked: asked, request: request)
                    if let approve = context.approve, await approve(question) {
                        return .run(
                            context.with(
                                request.granted(over: context.sandbox, workingDirectory: context.workingDirectory)))
                    }
                    return .refused(
                        .error(
                            "This call asked for " + asked.joined(separator: " and ")
                                + ". Only the user can widen the sandbox: run it within what is allowed, or ask the user."
                        ))
                case .invalid(let reason): return .refused(.error("Invalid sandbox for \(name): \(reason)."))
            }
        } catch {
            return .refused(.error("Invalid sandbox for \(name): \(error)."))
        }
    }
}
