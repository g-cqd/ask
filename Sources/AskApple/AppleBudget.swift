/// How the on-device window is shared between the instructions, the tools, the conversation and the reply. All in tokens, then as characters
/// by ``ApplePrompt/charactersPerToken``, because the window is small enough that a guess too high is a refused request.
struct AppleBudget: Equatable {
    let window: Int
    let reply: Int

    /// A budget for `window` tokens and a reply of at most `requested` tokens.
    init(window: Int, requested: Int) {
        self.window = window
        // A reply never takes more than a quarter of the window, so there is room left to say what it replies to.
        reply = Swift.max(64, Swift.min(requested, window / 4))
    }

    /// The tools' share: half, so that every tool ask has can be offered whenever the window can hold them; one that does not fit is left out and
    /// said (ADR-0120).
    var toolTokens: Int { window / 2 }
    /// What the conversation is always left, whatever the instructions and tools take: a quarter.
    var conversationFloor: Int { window / 4 }
    /// The instructions' share once the tools are known: everything the floor leaves, and never less than a fifth, so the project's own
    /// instruction files reach the model whenever there is room for them.
    func instructionTokens(tools: Int) -> Int {
        Swift.max(window / 5, window - reply - tools - conversationFloor - 64)
    }
    /// What is left for the conversation once the others are spent.
    func conversationTokens(instructions: Int, tools: Int) -> Int {
        Swift.max(window / 8, window - reply - instructions - tools - 64)
    }
}
