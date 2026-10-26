/// A line the running command is waiting for: a code to paste, an address, an API key. Typed into a buffer of its own, so a secret is
/// never in the draft, the transcript or a session file.
public struct PendingInput: Sendable, Equatable {
    /// Which question it is, so the answer reaches the command that asked.
    public let id: Int
    public let prompt: String
    /// Whether what is typed is hidden.
    public let secret: Bool

    /// The question and what is typed so far, for the status line: dots and a count for a secret, the end of the text otherwise.
    func line(typed: String) -> String {
        let shown: String
        if secret {
            shown = typed.isEmpty ? "" : String(repeating: "•", count: Swift.min(typed.count, 12)) + " (\(typed.count))"
        } else {
            shown = typed.count > 40 ? "…" + typed.suffix(39) : typed
        }
        return "\(prompt) › \(shown) · Enter sends · Esc cancels"
    }
}
