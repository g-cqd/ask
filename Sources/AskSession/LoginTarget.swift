internal import AskAI

/// The names `ask logout` takes for the accounts ask itself keeps, which a named connection may not shadow.
enum LoginTarget {
    /// Whether `name` is one of the built-in sign-ins rather than a named connection or a stored key.
    static func builtIn(_ name: String) -> Bool {
        (LoginRequest.accounts + ["anthropic", "openai"]).contains(name)
    }
}
