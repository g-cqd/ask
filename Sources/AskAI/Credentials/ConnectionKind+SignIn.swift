extension ConnectionKind {
    /// The word a person signs in with, which names the connections a second sign-in makes.
    var signInName: String { self == .codex ? "codex" : "claude" }
}
