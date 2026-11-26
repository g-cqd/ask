internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization
internal import System

/// A thread's own model (owner, 2026-11-26).
extension AgentConversation {
    /// `/model` in thread `id`'s lane (owner, 2026-11-26): says the model it works with; `/model WORD` gives it its own from its next
    /// run, as `/model` reads its word, refused when it does not resolve or the organisation requires one; `/model reset` takes it away.
    func threadModel(_ id: String, arguments: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
        Task { await threadModel(id, arguments: arguments, update: update) }
    }

    func threadModel(_ id: String, arguments: String, update: @escaping @Sendable (ConversationUpdate) -> Void) async {
        guard let thread = threads.thread(id) else { return }
        let say: @Sendable (String, Bool) -> Void = { update(.thread(id: id, .notice($0, isError: $1))) }
        guard let request = Self.parseModel(arguments) else {
            say("Usage, in a thread's lane: /model [CONNECTION] MODEL, or /model reset.", true)
            return
        }
        let word: String?
        switch request {
            case .show:
                let label = await threadModelLabel(thread.model)
                let whose = thread.model != nil ? "its own" : "threads.model or the conversation's"
                say("\(id) works with \(label) (\(whose)).", false)
                return
            case .reset: word = nil
            case .choose(let provider, let model):
                if let refusal = modelRequired() {
                    say(refusal, true)
                    return
                }
                word = provider.map { "\($0)/\(model)" } ?? model
        }
        if let word {
            do { _ = try await settings(forModel: word) } catch {
                say("Model not changed: \(word) does not resolve: \(error)", true)
                return
            }
        }
        threads.setModel(id, to: word)
        let label = await threadModelLabel(word)
        let when = thread.state.isActive ? "from its next run" : "from its next message"
        say("\(id) works with \(label) \(when); main keeps its model.", false)
        update(.thread(id: id, .label(label)))
    }
}
