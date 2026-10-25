internal import Foundation

// @dl:accept -- each section decodes its keys through the one shared walk; the key tables are the data
extension ConfigurationFile {
    /// The `mcp` object: a server for each key.
    struct MCPDecoded: Decodable {
        var section = MCPSection()
        init(from decoder: any Decoder) throws {
            // @dl:accept -- the walk the key tables share
            var servers: [MCPServerSetting] = []
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                servers.append(try container.decode(MCPServerDecoded.self, forKey: key).server(named: key.stringValue))
            }
            section = MCPSection(servers: servers)
        }
    }

    /// One server's keys; unknown keys are refused.
    struct MCPServerDecoded: Decodable {
        var server = MCPServerSetting(name: "")  // @dl:accept -- a key table decoded through the shared walk
        init(from decoder: any Decoder) throws {
            // @dl:accept -- the walk the key tables share
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                switch key.stringValue {
                    // @dl:accept -- the key tables are the data, and the walk over them is already shared
                    case "command": server.command = try container.decode(String.self, forKey: key)
                    case "args": server.args = try container.decode([String].self, forKey: key)
                    case "env": server.env = try container.decode([String: String].self, forKey: key)
                    // @dl:accept -- a key table row
                    case "cwd": server.cwd = try container.decode(String.self, forKey: key)
                    case "url": server.url = try container.decode(String.self, forKey: key)
                    case "headers": server.headers = try container.decode([String: String].self, forKey: key)
                    case "tools": server.tools = try container.decode([String].self, forKey: key)
                    case "enabled": server.enabled = try container.decode(Bool.self, forKey: key)
                    default: throw UnknownKey(key: "mcp.<server>." + key.stringValue)
                }
            }
        }

        func server(named name: String) -> MCPServerSetting {
            var named = server
            named.name = name
            return named
        }
    }

    /// Whether each server is one thing or the other, with the keys that thing has, and named so a tool's name can carry it. A project's
    /// file may name servers (it is read only once the person has trusted it, and trusting says what would start), but may not read ask's
    /// environment into them: `${NAME}` in a project's file could carry a key to a server the repository chose.
    static func validateMCP(_ section: MCPSection?, path: String, isProject: Bool) throws(ConfigurationError) {
        guard let section else { return }
        for server in section.servers {
            try validate(server, path: path)
            guard isProject else { continue }
            for (part, values) in [("env", server.env), ("headers", server.headers)]
            where values.values.contains(where: MCPServerSetting.referencesEnvironment) {
                throw .outOfRange(
                    path: path, key: "mcp.\(server.name).\(part)",
                    reason:
                        "uses ${NAME} in a project's file: that would read your environment into a server the repository chose; write the value, or name the server in your own config file"
                )
            }
        }
    }

    private static func validate(_ server: MCPServerSetting, path: String) throws(ConfigurationError) {
        let key = "mcp.\(server.name)"
        func refuse(_ part: String, _ reason: String) -> ConfigurationError {
            .outOfRange(path: path, key: part.isEmpty ? key : key + "." + part, reason: reason)
        }
        guard MCPServerSetting.isValid(name: server.name) else {
            throw refuse(
                "",
                "is not a usable name: use 1 to 32 letters, digits, - and _, not starting with -, and no double underscore"
            )
        }
        switch (server.command, server.url) {
            case (nil, nil): throw refuse("", "needs a \"command\" or a \"url\"")
            case (.some, .some): throw refuse("", "has both a \"command\" and a \"url\": it is one or the other")
            case (.some(let command), nil):
                if command.isEmpty { throw refuse("command", "is empty") }
                if !server.headers.isEmpty { throw refuse("headers", "belongs to a \"url\" server") }
            case (nil, .some(let url)):
                guard let scheme = URL(string: url)?.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                    throw refuse("url", "must be an http or https address")
                }
                if !server.args.isEmpty { throw refuse("args", "belongs to a \"command\" server") }
                if !server.env.isEmpty { throw refuse("env", "belongs to a \"command\" server") }
                if server.cwd != nil { throw refuse("cwd", "belongs to a \"command\" server") }
        }
        if let tools = server.tools, tools.isEmpty || tools.contains("") {
            throw refuse("tools", "must list tool names, none of them empty; leave it out to offer every tool")
        }
    }
}
