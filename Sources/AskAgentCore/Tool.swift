internal import AemiJSON
public import AskAI

/// What a tool returns. A failure is an output too: the model reads it and decides what to do next.
public struct ToolOutput: Sendable, Equatable {
    public var content: String
    public var isError: Bool

    /// An output with this content.
    public init(_ content: String, isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    /// A failed outcome, explained for the model.
    public static func error(_ content: String) -> ToolOutput { ToolOutput(content, isError: true) }
}

/// Where a tool runs.
public struct ToolContext: Sendable, Equatable {
    /// Relative paths resolve against this directory.
    public let workingDirectory: String

    /// A context rooted at `workingDirectory`.
    public init(workingDirectory: String) { self.workingDirectory = workingDirectory }
}

/// Decoded arguments, or the error output that explains why they could not be decoded.
public enum ToolArguments<Value> {
    case success(Value)
    case failure(ToolOutput)
}

/// A capability the model can call. Implementations live in AskTools; the loop owns this contract.
///
/// `run` never throws: every outcome, including a failure, is an output. It should return promptly when its
/// task is cancelled.
public protocol Tool: Sendable {
    var definition: ToolDefinition { get }
    func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput
}

extension Tool {
    /// Decodes `input` into the tool's arguments.
    /// - Returns: the arguments, or an error output naming the tool, as the model knows it, and the problem.
    public func arguments<Value: Decodable>(_ type: Value.Type, from input: JSONObject) -> ToolArguments<Value> {
        do {
            return .success(try AemiJSON.JSONDecoder().decode(Value.self, from: input.bytes))
        } catch {
            return .failure(.error("Invalid arguments for \(definition.name): \(error)"))
        }
    }
}

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
