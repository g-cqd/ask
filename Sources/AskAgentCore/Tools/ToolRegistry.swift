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
    /// Whether something a call started still runs: it cannot adopt a narrower sandbox, so the session is not narrowed under it.
    let busy: @Sendable () -> Bool

    /// A registry of `tools`, in the order given, capping outputs with `cap`, and after them whatever `live` offers.
    /// - Parameters:
    ///   - tools: the tools, in the order a request lists them.
    ///   - cap: what bounds an output a tool did not bound itself.
    ///   - live: where tools that come and go are read, each time.
    ///   - busy: whether something an earlier call started still runs; the default says nothing does.
    /// - Throws: ``DuplicateName`` when two tools share a name.
    public init(
        _ tools: [any Tool],
        cap: OutputCap = .standard,
        live: LiveTools? = nil,
        busy: @escaping @Sendable () -> Bool = { false }
    ) throws(DuplicateName) {
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
        self.busy = busy
    }

    /// The tools' definitions, for the request.
    public var definitions: [ToolDefinition] {
        order.compactMap { tools[$0]?.definition } + offered().map(\.definition)
    }

    /// What the live tools offer now, without the names the built-in tools hold.
    private func offered() -> [any Tool] { live?.snapshot(excluding: Set(order)) ?? [] }

    /// Runs the tool called `name`.
    /// - Returns: its output, capped unless the tool bounded it itself, or an error output when no tool has that name.
    public func run(name: String, input: JSONObject, in context: ToolContext) async -> ToolOutput {
        var context = context
        if let gate = context.callGate {
            switch gate.policy.decide(tool: name, input: input, workingDirectory: context.workingDirectory) {
                case .run: break
                case .runWithoutServerQuestion: context = context.withoutServerQuestion()
                case .ask(let approval):
                    switch await gate.first?(approval) ?? .ask {
                        case .approve: break
                        case .refuse(let reason): return .error(reason)
                        case .ask:
                            guard await gate.ask(approval) else { return .error("The user did not allow this call.") }
                    }
            }
        }
        // The session's narrowing applies to every call, and a call may narrow further, never widen (roadmap 0019).
        let narrowed = context.narrowing?.policy.map { context.with(context.sandbox.intersecting($0)) } ?? context
        var output: ToolOutput
        var said: String?
        if let tool = tools[name] {
            switch await applyingRequest(of: name, input: input, to: narrowed, unnarrowed: context) {
                case .run(let asked, let outcome):
                    output = await tool.run(input, in: asked)
                    said = outcome
                case .refused(let refusal): return refusal
            }
        } else if let tool = offered().first(where: { $0.definition.name == name }) {
            // A foreign tool's arguments are its own: a `sandbox` among them is not a request to narrow ask's sandbox.
            output = await tool.run(input, in: narrowed)
        } else {
            let names = order + offered().map(\.definition.name)
            return .error("No tool is named \(name). Available: \(names.joined(separator: ", ")).")
        }
        if !output.bounded { output.content = cap.apply(output.content) }
        // What became of the session's sandbox is said once, above what the call itself gave (ADR-0162).
        if let said { output.content = output.content.isEmpty ? said : said + "\n" + output.content }
        return output
    }
}
