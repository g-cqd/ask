/// Where the session keys' questions are put (ADR-0138, idea i1): the terminal before a screen exists, or the screen once it is up.
protocol SetupInteraction: SignInInteraction {
    /// One of `choices`, by its index; `fallback` when the person just pressed Return, nil when they closed the question.
    func choose(_ question: String, header: String, _ choices: [String], fallback: Int) async -> Int?
    /// Shows `text`, which holds a secret to be read once (a recovery code), until the person presses Return; then it is gone from the
    /// screen, where there is one.
    func showOnce(_ text: String) async
}
