/// One MCP server the user named (ADR-0099): a program to run, or a URL to speak to, and what to use of it.
public struct MCPServerSetting: Sendable, Equatable {
    /// The name the configuration gave it. It is part of every tool's name (`mcp__<name>__<tool>`), so its letters are limited.
    public var name: String
    /// The program, for a server ask starts.
    public var command: String?
    /// Its arguments.
    public var args: [String]
    /// Variables to set for it, over the minimal environment it is given. A value may name one of ask's own as `${NAME}`.
    public var env: [String: String]
    /// Where it runs, or nil for where ask runs.
    public var cwd: String?
    /// The address, for a server that is a web service.
    public var url: String?
    /// Header fields to send to it. A value may name a variable of ask's own as `${NAME}`: a token need not be in the file.
    public var headers: [String: String]
    /// The tools to offer the model, by the server's own names; nil offers all of them if there are few enough.
    public var tools: [String]?
    /// Whether ask connects to it at all.
    public var enabled: Bool

    /// A server with these settings.
    public init(
        name: String, command: String? = nil, args: [String] = [], env: [String: String] = [:], cwd: String? = nil,
        url: String? = nil, headers: [String: String] = [:], tools: [String]? = nil, enabled: Bool = true
    ) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.cwd = cwd
        self.url = url
        self.headers = headers
        self.tools = tools
        self.enabled = enabled
    }

    /// Whether `name` can be part of a tool's name: letters, digits, `-` and `_`, from 1 to 32 characters, not starting with `-`, and no
    /// `__`, which separates the parts of the tool's name.
    public static func isValid(name: String) -> Bool {
        guard (1 ... 32).contains(name.utf8.count), name.first != "-", !name.contains("__") else { return false }
        return name.utf8.allSatisfy { byte in
            (0x30 ... 0x39).contains(byte) || (0x41 ... 0x5A).contains(byte) || (0x61 ... 0x7A).contains(byte)
                || byte == 0x2D || byte == 0x5F
        }
    }
}
