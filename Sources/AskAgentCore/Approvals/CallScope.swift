/// What a call asks about, and so what an "Allow for the session" answer remembers (roadmap 0134).
public enum CallScope: Sendable, Equatable {
    /// A command line: its subcommands, or its programs, for the session.
    case command(CommandWords)
    /// A file written or edited: further writes and edits of it, for the session.
    case file(String)
    /// Any other tool: its later calls, for the session.
    case tool(String)
}
