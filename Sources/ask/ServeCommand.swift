internal import ArgumentParser
internal import AskACP
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
            sessions: { folder in
                let made = try await sessions.make(in: folder)
                return ACPSession(id: made.id, folder: made.folder, conversation: made.conversation)
            },
            load: { id, folder in
                guard let loaded = try await sessions.load(id, in: folder) else { return nil }
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
}
