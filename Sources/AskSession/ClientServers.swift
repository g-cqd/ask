internal import AskAgentCore

/// The MCP servers a client gave a session (ADR-0154), as settings ask can run. A client names a server for a person to read
/// and ask names it in every tool's name, so the name is made one ask allows; and a server ask starts runs in the session's
/// folder, since `ask serve` itself runs wherever the client started it.
enum ClientServers {
    /// `servers` with names ask allows, no two the same, and each started program in `workspace` unless it says where.
    static func settings(_ servers: [MCPServerSetting], in workspace: String) -> [MCPServerSetting] {
        var taken: Set<String> = []
        return servers.map { asked in
            var server = asked
            server.name = unique(allowed(asked.name), among: taken)
            taken.insert(server.name)
            if server.command != nil, server.cwd == nil { server.cwd = workspace }
            // Security review 2026-11-25 (N-A4): MCP servers passed by an ACP client are untrusted like project servers,
            // so run them inside Seatbelt unless explicitly opted out in the server setting.
            server.definedByProject = true
            return server
        }
    }

    /// `name` with what a tool's name cannot hold replaced: a letter, a digit, `-` or `_` stays, anything else is a `-`; no `__`,
    /// no `-` first, at most 32 characters; `server` when nothing is left.
    static func allowed(_ name: String) -> String {
        var made = ""
        for character in name.unicodeScalars {
            let kept = character.isASCII && (character.properties.isAlphabetic || ("0" ... "9").contains(character))
            let next: Character = kept || character == "-" || character == "_" ? Character(character) : "-"
            if made.isEmpty, next == "-" { continue }
            if next == "_", made.last == "_" { continue }
            made.append(next)
        }
        made = String(made.prefix(32))
        return made.isEmpty ? "server" : made
    }

    /// `name`, or `name-2`, `name-3`…, whichever is first not `taken`; cut so that it still fits.
    private static func unique(_ name: String, among taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        var count = 2
        while true {
            let suffix = "-\(count)"
            let candidate = String(name.prefix(32 - suffix.count)) + suffix
            if !taken.contains(candidate) { return candidate }
            count += 1
        }
    }
}
