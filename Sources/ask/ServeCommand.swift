internal import ArgumentParser
internal import AskACP

/// `ask serve`: ask as an agent an editor drives, speaking the Agent Client Protocol on standard input and output (ADR-0153).
/// Standard output carries the protocol and nothing else. Not listed in the help until a session can be served: so far it
/// answers `initialize` (roadmap 0234 step 2).
struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Speak the Agent Client Protocol on standard input and output, for an editor to drive ask.",
        shouldDisplay: false
    )

    func run() async {
        // ask has no version yet (roadmap 0070): "0", as its other identities say.
        await ACPServer.serveStandardStreams(agent: ACPImplementation(name: "ask", title: "ask", version: "0"))
    }
}
