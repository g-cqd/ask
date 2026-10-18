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
        var output = await tool.run(input, in: context)
        output.content = cap.apply(output.content)
        return output
    }
}
