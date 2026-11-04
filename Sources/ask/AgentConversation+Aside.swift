internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization

/// `/btw QUESTION` (roadmap 0194): asked at once, during a turn too, answered over the conversation so far in a block of its own colour,
/// and never added to the conversation.
extension AgentConversation {
    func aside(_ question: String, update: @Sendable (ConversationUpdate) -> Void) async {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            update(.notice("Usage: /btw QUESTION asks beside the conversation, which it does not join.", isError: true))
            return
        }
        let id = "btw-" + UUID().uuidString
        update(.asideStarted(id: id, question: question))
        do {
            let loop = try agentLoop()
            let tree = session.withLock { $0?.tree }
            let (answer, spent) = try await loop.aside(question, over: tree)
            usage.withLock { $0.addBeside(spent) }
            update(.status(usage.withLock { $0.compact }))
            let shown = answer.allSatisfy(\.isWhitespace) ? "The model gave no answer in text." : answer
            update(
                .asideFinished(
                    id: id,
                    answer.allSatisfy(\.isWhitespace) ? .failed("no answer") : .succeeded,
                    answer: shown
                )
            )
        } catch {
            update(.asideFinished(id: id, .failed("failed"), answer: "The aside could not be answered: \(error)"))
        }
    }
}
