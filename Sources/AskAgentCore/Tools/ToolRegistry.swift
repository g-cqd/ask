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
        // A call may narrow its own sandbox, never widen it (roadmap 0019).
        var context = context
        do {
            if let request = try SandboxRequest.in(input) {
                switch request.applied(to: context.sandbox, workingDirectory: context.workingDirectory) {
                    case .narrowed(let policy):
                        context = ToolContext(
                            workingDirectory: context.workingDirectory, outputDirectory: context.outputDirectory,
                            sandbox: policy)
                    case .refused(let asked):
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
