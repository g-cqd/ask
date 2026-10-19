internal import Synchronization

@testable import AskAI

/// The prompts a sign-in showed, in order.
final class PromptLog: Sendable {
    private let prompts = Mutex<[SignInPrompt]>([])
    var all: [SignInPrompt] { prompts.withLock { $0 } }
    func add(_ prompt: SignInPrompt) { prompts.withLock { $0.append(prompt) } }
}
