internal import ArgumentParser
internal import AskACP
internal import AskAgentCore
internal import AskSession

/// `ask serve`: ask as an agent an editor drives, speaking the Agent Client Protocol on standard input and output (ADR-0153).
/// Standard output carries the protocol and nothing else. Each session the client asks for is a conversation of its own, in the
/// folder the client names (ADR-0154). Not listed in the help yet: it serves prompts and answers, and not yet tool calls,
/// approvals or cancellation (roadmap 0234 step 2).
struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Speak the Agent Client Protocol on standard input and output, for an editor to drive ask.",
        shouldDisplay: false
    )

    func run() async {
        let sessions = ServedSessions()
        // ask has no version yet (roadmap 0070): "0", as its other identities say.
        await ACPServer.serveStandardStreams(
            agent: ACPImplementation(name: "ask", title: "ask", version: "0"),
            sessions: { asked in
                let made = try await sessions.make(
                    in: asked.cwd,
                    asksPerson: asked.showsForms,
                    servers: Self.settings(asked.servers)
                )
                return ACPSession(id: made.id, folder: made.folder, conversation: made.conversation)
            },
            load: { id, asked in
                let servers = Self.settings(asked.servers)
                guard
                    let loaded = try await sessions.load(
                        id,
                        in: asked.cwd,
                        asksPerson: asked.showsForms,
                        servers: servers
                    )
                else { return nil }
                let made = loaded.made
                return ACPSession.Loaded(
                    session: ACPSession(id: made.id, folder: made.folder, conversation: made.conversation),
                    history: loaded.history
                )
            }
        )
        // The client has gone: what its sessions left running goes with it.
        await sessions.stopAll()
    }

    /// A client's MCP servers as ask's settings name one; their names are made ones ask allows where the session is made.
    private static func settings(_ servers: [ACPMCPServer]) -> [MCPServerSetting] {
        servers.map {
            MCPServerSetting(
                name: $0.name,
                command: $0.command,
                args: $0.args,
                env: $0.env,
                url: $0.url,
                headers: $0.headers
            )
        }
    }
}
