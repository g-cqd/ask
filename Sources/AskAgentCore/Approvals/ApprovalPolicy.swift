internal import AemiJSON
public import AskAI
internal import Foundation

/// Which tool calls ask the person before they run (roadmap 0134). On by default; read-only tools exempt; the person's `approvals`
/// lists over that; `--yes` allows everything and `--ask-always` asks even what the configuration allows. MCP tools keep their own rule
/// (they ask unless their server says they are read-only, 0153) unless a list names them.
public struct ApprovalPolicy: Sendable, Equatable {
    /// A command-line flag over the configuration.
    public enum Flag: Sendable, Equatable { case yes, askAlways }

    /// What to do with one call.
    public enum Decision: Sendable, Equatable {
        case run
        case ask(ToolCallApproval)
        /// Run, and without the server's own question: the person's `allow` list names it.
        case runWithoutServerQuestion
    }

    public let section: ApprovalsSection
    public let flag: Flag?
    /// What the command line allows for this run (`--allow`), added to the section's `allow` list (roadmap 0156).
    public let allowing: [String]

    public init(section: ApprovalsSection = ApprovalsSection(), flag: Flag? = nil, allowing: [String] = []) {
        self.section = section
        self.flag = flag
        self.allowing = allowing
    }

    /// What to do with a call of `tool` with `input`; relative paths resolve against `workingDirectory`.
    public func decide(tool: String, input: JSONObject, workingDirectory: String) -> Decision {
        // `mcp_call` is judged as the tool it calls, so the lists name MCP tools one way.
        let tool = Self.calledTool(tool, input) ?? tool
        if flag == .yes { return Self.isMCP(tool) ? .runWithoutServerQuestion : .run }
        let ask = ToolCallApproval(tool: tool, input: input, scope: Self.scope(of: tool, input, workingDirectory))
        if Self.matches(section.ask, tool) { return .ask(ask) }
        if flag != .askAlways, Self.matches((section.allow ?? []) + allowing, tool) {
            return Self.isMCP(tool) ? .runWithoutServerQuestion : .run
        }
        if Self.isMCP(tool) { return .run }
        guard Self.changesThings(tool, input) else { return .run }
        if flag != .askAlways, section.defaultMode == .allow { return .run }
        return .ask(ask)
    }

    /// The built-in tools that change things: commands, files, and what is typed into a job.
    private static func changesThings(_ tool: String, _ input: JSONObject) -> Bool {
        switch tool {
            case "bash", "write", "edit": true
            case "job": fields(of: input).action == "input"
            default: false
        }
    }

    /// `mcp__server__tool` for an `mcp_call` of `tool` on `server`.
    private static func calledTool(_ tool: String, _ input: JSONObject) -> String? {
        guard tool == "mcp_call", let server = fields(of: input).server, let called = fields(of: input).tool else {
            return nil
        }
        return "mcp__\(server)__\(called)"
    }

    private static func isMCP(_ tool: String) -> Bool { tool.hasPrefix("mcp__") || tool == "mcp_call" }

    /// Whether `names` holds `tool`, a pattern ending in `*` that it starts with, `all` (every tool), or `commands` (`bash`).
    private static func matches(_ names: [String]?, _ tool: String) -> Bool {
        (names ?? [])
            .contains { name in
                switch name {
                    case "all": true
                    case "commands": tool == "bash"
                    default: name.hasSuffix("*") ? tool.hasPrefix(name.dropLast()) : name == tool
                }
            }
    }

    private static func scope(of tool: String, _ input: JSONObject, _ workingDirectory: String) -> CallScope {
        switch tool {
            case "bash": return .command(CommandWords(fields(of: input).command ?? ""))
            case "write", "edit":
                guard let path = fields(of: input).path else { return .tool(tool) }
                let absolute = path.hasPrefix("/") ? path : workingDirectory + "/" + path
                return .file((absolute as NSString).standardizingPath)
            default: return .tool(tool)
        }
    }

    /// The fields of `input` the policy reads, all nil when it has none of them.
    private static func fields(of input: JSONObject) -> Fields {
        (try? AemiJSON.JSONDecoder().decode(Fields.self, from: input.bytes)) ?? Fields()
    }

    /// The fields of a call the policy reads.
    private struct Fields: Decodable {
        var command: String?
        var path: String?
        var action: String?
        var server: String?
        var tool: String?
    }
}
