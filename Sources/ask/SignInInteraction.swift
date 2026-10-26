/// How a sign-in talks to the person: the command line writes and reads the terminal, the screen shows notices and asks in its prompt. The
/// sign-in itself is written once, over this (ADR-0117).
protocol SignInInteraction: Sendable {
    /// Shows `text`, now.
    func say(_ text: String)
    /// Asks for a line. A secret is not echoed and not kept in the transcript. Nil when the person cancelled.
    func ask(_ prompt: String, secret: Bool) async -> String?
}
